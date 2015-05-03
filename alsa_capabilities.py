#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os, stat
import sys
#import shutil
import subprocess
#import tempfile
import errno
import re
import socket # for getting the hostname
from signal import signal, SIGPIPE, SIG_DFL
import argparse

appname="alsacapabilities"
appversion="0.0.1"

class class_alsa_interface:
    """A custom class to hold information about an alsa audio output interface.
    Initialize it with an output line of `aplay -l' which starts with `card', like
    `card 0: MID [HDA Intel MID], device 0: ALC888 Analog [ALC888 Analog]'."""

    def __init__(self, rawoutputline):
        #, monitor, device_label, label, uac_class, audioformat, chardev):
        self.rawoutputline = rawoutputline.decode().split(',')
        self.cardfull = self.rawoutputline[0].strip()
        self.cardarray = self.cardfull.strip().split(':')
        self.cardnr = self.cardarray[0].strip().split(' ')[1].strip()
        self.cardname_raw = re.split(r'[\[\]]', self.cardarray[1])
        self.cardname_system = self.cardname_raw[0].strip()        
        self.cardname_label = self.cardname_raw[1].strip()
        
        self.devicefull = self.rawoutputline[1].strip()
        self.devicearray = self.devicefull.strip().split(':')
        self.devicenr = self.devicearray[0].strip().split(' ')[1].strip()
        self.devicename_raw = re.split(r'[\[\]]', self.devicearray[1])
        self.devicename_system = self.devicename_raw[0].strip()
        self.devicename_label = self.devicename_raw[1].strip()


        
        self.address = "hw:{0},{1}".format(self.cardnr, self.devicenr)

        self.displaylabel = "`{}' output of sound device `{}' on host `{}'".format(self.devicename_label, self.cardname_label, socket.gethostname())


        self.chardev = os.path.join('/', 'dev', 'snd', "pcmC{0}D{1}p".format(self.cardnr, self.devicenr))

        uac_kernel_driver="snd_usb_audio"
        self.uac_class = ""
        self.is_uac = self.get_uac_class()
        if self.is_uac:
            self.uac_driver_nrpacks = self.get_kernel_parameter(uac_kernel_driver, "nrpacks")        
        
        self.electrical_interface = ""
        self.get_electrical_interface()
        
        #self.interfacetype = "{}".format(self.electrical_interface)

        self.monitorfile = os.path.join('/', 'proc', 'asound', 'card{0}'.format(self.cardnr), 'pcm{0}p'.format(self.devicenr), 'sub0', 'hw_params')
        self.streamfile = self.monitorfile
        try:
            self.monitorfile_accessible=stat.S_ISCHR(os.stat(self.monitorfile).st_mode)
            self.monitorfile_accessible=True
            try: 
                with open (self.monitorfile, "r") as hw_params:
                    data=hw_params.read().replace('\n', '')
                    if data == "closed":
                        self.monitorfile_status="closed"
                    else:
                        self.monitorfile_status="opened"
            except:
                self.monitorfile_accessible=False
                self.monitorfile_status="(unknown)"
        except:
            self.monitorfile_accessible=False
            self.monitorfile_status="(unknown)"
            
        self.sampleformats_error = ""
        self.sampleformats = self.get_sampleformats()
        
        self.chardev_accessible = ( len(self.sampleformats_error) == 0 )

    def get_electrical_interface(self):
        found_digital  = False
        eif_suffix="audio output interface"
        filter_digital="""ADAT
AES
EBU
AES/EBU
Digital
DSD
HDMI
i2s
iec958
SPDIF
s/pdif
Toslink
UAC
USB"""
        for line in iter(filter_digital.splitlines()):
            if re.search(line, self.displaylabel, re.IGNORECASE):
                #print("found: {}".format(line))
                if line == "Digital":
                    self.electrical_interface = "Digital {}".format(eif_suffix)
                else:
                    self.electrical_interface = "Digital ({}) {}".format(line, eif_suffix)                  
                found_digital = True
                break
        
        if not found_digital:
            if re.search("analog", self.displaylabel, re.IGNORECASE):
                self.electrical_interface = "Analog {}".format(eif_suffix)
            else:
                self.electrical_interface = "Unknown"

        
    def printlist(self):
        msg_chardev_accessible="in use"
        if self.chardev_accessible:
            msg_chardev_accessible="not {}".format(msg_chardev_accessible)

        msg_monitorfile_accessible="accessible"
        if not self.monitorfile_accessible:
            msg_monitorfile_accessible="not {}".format(msg_monitorfile_accessible)

           
        print("* {}".format(self.displaylabel))
        print("  - hardware address  = {}".format(self.address))
        print("  - electrical        = {}".format(self.electrical_interface))        
        print("  - character device  = {} ({})".format(self.chardev, msg_chardev_accessible))
        print("  - monitor file      = {} ({}, {})".format(self.monitorfile, msg_monitorfile_accessible, self.monitorfile_status))
        print("  - usb audio class   = {}".format(self.uac_class))
        print("  - sample formats    = {}".format(', '.join(self.sampleformats)))        
        
        #print("  - sound device            = {}".format(self.cardname))
        print("")
        

    def inspect_chardev(self):
        processes = []
        pname = ""
        pid=""
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
        for line in stdout_value.decode().splitlines():
            match = re.match(r'^(?P<key>[cp])(?P<value>.*)',line)
            if match:
                if match.group('key') == "p": pid=match.group('value')
                if match.group('key') == "c": pname=match.group('value')
                result = "process `{}' with pid `{}'".format(pname, pid)

        return result
        
        
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
        sampleformats=[]
        if re.search('Available formats.*', stderr_value.decode()):
      
            ## the lines in stderr starting with `- ' (after "Available formats:") 
            ## contain the available sample formats
            subscript_raw_output=stderr_value.decode().splitlines()

            for line in subscript_raw_output:
                match = re.match('- (.*)',line)
                if match:
                    sampleformats.append(match.group(1))
        else:
            ## aplay reported an error for this card
            ## errors are reported after the linenumber;
            ## use that to extract the message
            self.sampleformats_error = re.split('[0-9]:',stderr_value.decode())[1].strip()
            pname=self.inspect_chardev()
            sampleformats=['can\'t detect, device is in use by {})'.format(pname)]

            
        return sampleformats

    def get_uac_class(self):
        # returns a list containing class ID and description

        uac_result=False
        uac_result_msg=""
        msg_uac_iso="isochronous"
        usbout_classes={}
        usbout_classes["ADAPTIVE"] = [1, "{} adaptive".format(msg_uac_iso) ]
        usbout_classes["ASYNC"] = [2, "{} asynchronous".format(msg_uac_iso) ]
        streamfile_path = os.path.join("/","proc","asound","card{0}".format(self.cardnr), "stream0")
        
        self.uac_transfertype = "" # isochronous (| bulk)
        self.uac_synchtype = ""    # adaptive | asynchronous

        try: 
            with open (streamfile_path, "r") as streamfile_file:
                uac_streamfile_contents=streamfile_file.read().strip()
                uac_synctype_raw = re.split('.*Endpoint.*\((.*)\)', uac_streamfile_contents)[1]
                uac_result=True
                uac_result_msg='{}: {}'.format(str(usbout_classes[uac_synctype_raw][0]), usbout_classes[uac_synctype_raw][1])

        except IOError as err:
            ## device is not uac
            if err.errno == 2:     
                file = None
                uac_result_msg="(not applicable)"
            else:
                uac_result_msg="unable to determine. Error number {} ({}) while opening `{}' for reading".format(str(errno), err, streamfile_path)
            

        self.uac_class=uac_result_msg
        return uac_result

        

        
    def get_kernel_parameter(self, driver, parameter):
        ## returns the value of a parameter for a specific driver from sys
      
        parameter_path = os.path.join("/", "sys", "module", driver, "parameters", parameter)
        try: 
            with open (parameter_path, "r") as parameter_file:
                result=parameter_file.read().strip()
        except:
            result="could not open `{}' for reading".format(parameter_path)

        return result
                
          
    
    def iterate_fds(pid):
        # source: http://stackoverflow.com/questions/11114492/check-if-a-file-is-not-open-not-used-by-other-process-in-python/11115521#11115521
        dir = '/proc/'+str(pid)+'/fd'
        if not os.access(dir,os.R_OK|os.X_OK): return

        for fds in os.listdir(dir):
            for fd in fds:
                full_name = os.path.join(dir, fd)
                try:
                    file = os.readlink(full_name)
                    if file == '/dev/null' or \
                       re.match(r'pipe:\[\d+\]',file) or \
                       re.match(r'socket:\[\d+\]',file):
                        file = None
                except OSError as err:
                    if err.errno == 2:     
                        file = None
                    else:
                        raise(err)
                    
                yield (fd,file)        

    
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
        

    #def list_interfaces(self):
        #for i in self.interfaces:
            #sys.stderr.write("'%s' > '%s'\n" % (i.index, i.address))

def print_debug(debugmessage):
    sys.stderr.write(" Debug: %s\n" % debugmessage)

def get_raw_aplay_output():
    """returns the raw output of `aplay -l'"""
    cmd_aplay_list="LANG=C aplay -l 2>&1"
    try:
        script_output = subprocess.check_output(cmd_aplay_list, 
                                                shell=True, \
                                                stderr=None, \
                                                preexec_fn = lambda: signal(SIGPIPE, SIG_DFL))
    except:
        print("error running \`%s'" % cmd_aplay_list) 

    return script_output

def main():            
    ## main
    global aplay_raw_output
    parser = argparse.ArgumentParser(prog=appname,
                                     description="""Display the
                                     details of alsa audio output
                                     interfaces on the host running
                                     this program.""")
    
    parser.add_argument('--output', '-o', 
                        type=argparse.FileType('w'), 
                        help='Write the output to the file specified.', 
                        nargs='?', 
                        default=sys.stdout)

    ## todo: add shorthand options, eg. `-l u'
    parser.add_argument('--limit','-l',
                        choices=['a', 'analog', 'u', 'usb', 'uac', 'd', 'digital'],
                        default='',
                        type = str.lower,
                        help="""limit the output to that specified
                        with the limit of the interface type; a =
                        analog, u = usb or uac, d = digital (including
                        usb/uac).""",
                        nargs=1)
    
    parser.add_argument('--interface','-i', 
                        type=str, 
                        default='', 
                        help="""limit the output to that specified
                        with a hardware address in alsa style,
                        eg. `hw:x,y'.""",
                        nargs=1)
    
    parser.add_argument('--filter', '-f', 
                        type=str, 
                        default='', 
                        help="""limit the output to interfaces
                        matching the simple filter specified, ie.
                        -f 'Intel' matches cards with exact string \`Intel'.""",
                        nargs=1)  
    parser.add_argument('--regex', '-c', 
                        type=str, 
                        default='', 
                        help="""limit the output to interfaces
                        matching the regex filter specified, ie.
                        -f '[iI]ntel' matches cards with the strings \`Intel' and \`intel'.""",
                        nargs=1)  

    parser.add_argument('--debug', '-d', 
                        action="store_true", 
                        help="print status messages to stderr")

    parser.add_argument('--version', 
                        action="version",
                        version=appversion,
                        help="print version of the script")

    args = parser.parse_args()

    ## check if extensive information should be stored
    DEBUG=vars(args)['debug']
    if DEBUG:
        print_debug("main() started with options:")
        for key in vars(args):
            print_debug(" %s: %s" % (key, vars(args)[key]))


        if vars(args)['limit']:
            print("limit set to: %s" % vars(args)['limit'][0])
    
    aplay_raw_output = get_raw_aplay_output()
    ## create an empty list for holding interfaces with pairs of `('hw:a,b', 'Interface X on Y')'
    interfaces_list = []
    #print("script output: {}".format(script_output))
    #print("main iterating lines of output")
    for line in aplay_raw_output.splitlines():
        #print("line: {}".format(line))
        if re.split(r' ', line.decode())[0] == "card":
            #print("Main: interface line found")
            aif = class_alsa_interface(line)
            aif.printlist()
        

main()
