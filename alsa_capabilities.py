#!/usr/bin/python
# -*- coding: utf-8 -*-

import os, stat
import sys
import shutil
import subprocess
import tempfile
import errno
import re
import socket # for getting the hostname
from signal import signal, SIGPIPE, SIG_DFL

from optparse import OptionParser

class class_alsa_interface:
    """A custom class to hold information about an alsa audio output interface.
    Initialize it with an output line of `aplay -l' which starts with `card', like
    `card 0: MID [HDA Intel MID], device 0: ALC888 Analog [ALC888 Analog]'."""

    def __init__(self, rawoutputline):
        #, monitor, device_label, label, uacclass, audioformat, chardev):
        self.rawoutputline = rawoutputline.decode().split(',')
        self.cardfull = self.rawoutputline[0].strip()
        self.cardarray = self.cardfull.strip().split(':')
        self.cardnr = self.cardarray[0].strip().split(' ')[1].strip()
        self.cardname = re.split(r'[\[\]]', self.cardarray[1])[1].strip()
        
        self.devicefull = self.rawoutputline[1].strip()
        self.devicearray = self.devicefull.strip().split(':')
        self.devicenr = self.devicearray[0].strip().split(' ')[1].strip()
        self.devicename = re.split(r'[\[\]]', self.devicearray[1])[1].strip()

        
        self.address = "hw:{0},{1}".format(self.cardnr, self.devicenr)

        self.displaylabel = "`{}' output of sound device `{}' on host `{}'".format(self.devicename, self.cardname, socket.gethostname())

        self.chardev = os.path.join('/', 'dev', 'snd', "pcmC{0}D{1}p".format(self.cardnr, self.devicenr))

        self.uacclass = "(not yet implemented)"
        self.electrical = ""
        if re.search('.*[Aa][Nn][Aa][Ll][Oo][Gg].*', self.displaylabel):
            self.electrical = "Analog"
        else:
            self.electrical = "Digital"
        self.interfacetype = "{} audio output interface (direct access)".format(self.electrical)

        self.streamfile = os.path.join('/', 'proc', 'asound', 'card{0}'.format(self.cardnr), 'pcm{0}p'.format(self.devicenr), 'sub0', 'hw_params')
        try:
            self.streamfile_accessible=stat.S_ISCHR(os.stat(self.streamfile).st_mode)
            self.streamfile_accessible=True
            try: 
                with open (self.streamfile, "r") as hw_params:
                    data=hw_params.read().replace('\n', '')
                    if data == "closed":
                        self.streamfile_status="closed"
                    else:
                        self.streamfile_status="opened"
            except:
                self.streamfile_accessible=False
                self.streamfile_status="(unknown)"
        except:
            self.streamfile_accessible=False
            self.streamfile_status="(unknown)"
            
        self.sampleformats_error = ""
        self.sampleformats = self.get_sampleformats()
        
        self.chardev_accessible = ( len(self.sampleformats_error) == 0 )

            
    def printlist(self):
        msg_chardev_accessible="in use"
        if self.chardev_accessible:
            msg_chardev_accessible="not {}".format(msg_chardev_accessible)

        msg_streamfile_accessible="accessible"
        if not self.streamfile_accessible:
            msg_streamfile_accessible="not {}".format(msg_streamfile_accessible)

           
        print("* {}".format(self.displaylabel))
        print("  - hardware address  = {}".format(self.address))

        print("  - sample formats    = {}".format(', '.join(self.sampleformats)))
        print("  - usb audio class   = {}".format(self.uacclass))
        print("  - character device  = {} ({})".format(self.chardev, msg_chardev_accessible))
        print("  - stream file       = {} ({}, {})".format(self.streamfile, msg_streamfile_accessible, self.streamfile_status))
        
        print("  - device type       = {}".format(self.interfacetype))
        #print("  - sound device            = {}".format(self.cardname))
        #print("  - output interface        = {}".format(self.devicename))
        print("")
        
        #self.monitor = self.getprop('monitor')
        #self.device_label = '' # device_label
        #self.label = label
        #self.uacclass = self.get_uacclass
        #self.audioformat = audioformat

    def inspect_chardev(self):
        processes = []
        cmd_lsof_chardev='/usr/bin/sudo /usr/bin/lsof -F c /dev/snd/pcmC{0}D{1}p 2>/dev/null'.format(self.cardnr, self.devicenr)
        #print(cmd_lsof_chardev)
        proc = subprocess.Popen(cmd_lsof_chardev.encode(),
                        shell=True,
                        stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE)
        stdout_value, stderr_value = proc.communicate(b'bla')
        #print("stdout: {}".format(stdout_value))
        #print("stderr: {}".format(stderr_value))
        
        
        
    def get_sampleformats(self):

        sampleformats = []
        cmd_aplay_urandom='cat /dev/urandom | LANG=C aplay -D "{}" >/dev/null'.format(self.address)
        #print(cmd_aplay_urandom)
        proc = subprocess.Popen(cmd_aplay_urandom.encode(),
                        shell=True,
                        stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE)
        stdout_value, stderr_value = proc.communicate(b'bla')
        #print("stdout: {}".format(stdout_value))
        #print("stderr: {}".format(stderr_value))
        if re.search('.*[Ee]rror.*', stderr_value.decode()):
            ## aplay reported an error for this card
            ## errors are reported after the linenumber;
            ## use that to extract the message
            self.sampleformats_error = re.split('[0-9]:',stderr_value.decode())[1].strip()
            sampleformats=['(device is in use, can\'t detect)']
            self.inspect_chardev()
            
        else:
            ## the lines in stderr after the third one ("Available formats:")
            ## contains the avaliable sample formats
            subscript_output=stderr_value.decode().splitlines()[3:]
            #print(subscript_output)
            ## extract the real values (each line contains "- SOMEFORMAT")
            ## and store them in a list
            sampleformats=[l.split('- ')[1] for l in subscript_output]
            
        return sampleformats
        
    
class class_alsa_system:
    """A class to hold information about a system running alsa."""
    def __init__(self):
        self.name = socket.gethostname()
        self.interfaces = []
        self.interfaces = self.get_interfaces()
        
    def get_interfaces(self):
        """Returns a list containing class_alsa_interface objects."""
        interfaceslist = []
        filecounter = 0
        

    def list_interfaces(self):
        for i in self.interfaces:
            sys.stderr.write("'%s' > '%s'\n" % (i.index, i.address))


def main():            
    ## main
    cmd_aplay_list="LANG=C aplay -l 2>&1"    
    script_output = subprocess.check_output(cmd_aplay_list, 
                                            shell=True, \
                                            stderr=None, \
                                            preexec_fn = lambda: signal(SIGPIPE, SIG_DFL))

    ## create an empty list for holding interfaces with pairs of `('hw:a,b', 'Interface X on Y')'
    interfaces_list = []
    #print("script output: {}".format(script_output))
    #print("main iterating lines of output")
    for line in script_output.splitlines():
        #print("line: {}".format(line))
        if re.split(r' ', line.decode())[0] == "card":
            #print("Main: interface line found")
            aif = class_alsa_interface(line)
            aif.printlist()
        

main()
