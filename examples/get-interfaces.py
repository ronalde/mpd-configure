#!/usr/bin/env python

import subprocess, os, re
from signal import signal, SIGPIPE, SIG_DFL

## limit the type of interfaces returned
limittype = 'analog'

## name of custom bash script, that sources `alsa-capabilities' which
## returns a string consiting of one line per interface, each with the
## format `Interface X on Y (hw:a,b)'
script = os.path.join('.', 'get-interfaces-for-python.sh')

## call the script, trapping std_err and storing std_out to `aif_output'
script_output = subprocess.check_output( 'LIMIT_INTERFACE_TYPE="%s" %s' % (limittype, script), \
                                      shell=True, 
                                      stderr=None, \
                                      preexec_fn = lambda: signal(SIGPIPE, SIG_DFL))

## create an empty list for holding interfaces with pairs of `('hw:a,b', 'Interface X on Y')'
interfaces_list = []

lenoflabel = 0 

## process each line of output (eg each interface)
for interface in script_output.splitlines():
    ## split the line on `()'
    interface_split = re.split(r'[()]', interface)
    ## store the label (eg. `Interface X on Y')
    interface_label = interface_split[0].strip()
    lenoflabel = len(interface_label) if len(interface_label) > lenoflabel else lenoflabel
    ## store the index (ef. `hw:a,b')
    interface_index =  interface_split[1]
    ## append the pair to the list
    interfaces_list.append((interface_index, interface_label))

## sample output
print "Found the following audio interfaces of type `%s':\n" % limittype
print "hwaddr  label                       "
print "%s  %s" % ('='*len('hwaddr'), '='*lenoflabel)
for aif in interfaces_list:
    print "%s  %s" % (aif[0].rjust(len('hwaddr')), aif[1])

