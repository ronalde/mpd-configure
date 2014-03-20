#!/usr/bin/env bash

## script to list alsa digital output devices by hardware address
## and the digital audio (output) formats they support
##
## source:    https://github.com/ronalde/mpd-configure
## also see:  http://lacocina.nl/2013/04/19/alsa-highres/

paconf=~/.pulse/client.conf
paconfbackup="${paconf}.da-backup"
paconfrestore="false"
paconfcreated="false"
defaultcard=""
alsaoutputdevices=0

LANG=C

checkparunning() {
    # check if pulseaudio is running for the current user
    parunning="$(pgrep -u ${USER} pulseaudio)"
}


pulserestoreconf() {
    if [ "${paconfcreated}" == "true" ]; then
	# conf file was created by this script; remove it
	rm "${paconf}"
    else
	if [ "${paconfrestore}" == "true" ]; then
	    # restore existing conf file
	    mv "${paconfbackup}" "${paconf}"
	fi
    fi
}

pulsebackupconf() {
    # remove existing script created backup file 
    if [ -f "${paconfbackup}" ] ; then
	rm "${paconfbackup}"
    fi
    # backup conf
    cp "${paconf}" "${paconfbackup}"
}

pulsekill() {

        # kill running pulseaudio for current user
	pulseaudio --kill
	
        # check if this succeeded
	pakillok="$(pgrep -u ${USER} pulseaudio)"
}

pulsedisable() {

    checkparunning

    if [ ! "$?" -eq "1" ]; then
	echo "pulseaudio is running; will temporary disable and stop it "
    	
        # temporary disable pulseaudio
	if [ -f "${paconf}" ] ; then
	    pulsebackupconf
	    if [ "$?" -eq "0" ]; then
		sed -i 's/autospawn[[:space:]]*=[[:space:]]*\([no]*\)/autospawn = no/gI' ${paconf} 
		paconfrestore="true"
	    fi
	else
	    echo "autospawn = no" > "${paconf}"
	    paconfcreated="true"
	fi
	
	pulsekill

	if [ -! "$?" -eq "1" ] ; then
	    # pulse is still running
	    pulserestoreconf
	    echo "Error: could not kill pulseaudio, exiting script ..."
	    exit 1
	fi
    fi
}

alsacards() {

    boutput=""
    
    # construct list of alsa digital outputs
    aplayoutput="$(aplay -l | grep ^card | grep -i -E 'usb|digital|hdmi|i2s|spdif|toslink|adat')"

    while read -r line; do

	# bashism
	if [[ "${line}" =~ "card "([0-9]*)": "(.*)" ["(.*)"], device "([0-9]*)": "(.*)" ["(.*)"]"(.*) ]]; then
	    let alsaoutputdevices+=1
	    cardnr="${BASH_REMATCH[1]}"
	    cardname="${BASH_REMATCH[2]}"
	    cardlabel="${BASH_REMATCH[3]}"
	    devnr="${BASH_REMATCH[4]}"
	    devname="${BASH_REMATCH[5]}"
	    devlabel="${BASH_REMATCH[6]}"
	    address="hw:${cardnr},${devnr}"

	    boutput=$(echo -e "${boutput}\n${alsaoutputdevices}) ${address} (Soundcard \"${cardlabel}\" with output device \"${devlabel}\")")

	    if [ ${alsaoutputdevices} -eq "1" ] ; then
		defaultcard="${address}"
	    fi
	fi

    done <<< "${aplayoutput}"

    echo -e "${boutput}"
}

alsadetect() {

    # list all alsa playback devices with their hw:x,y address
    echo -e "\nDetected alsa devices with digital outputs:"

    # fetch card list
    alsacards

    if [ ! "${alsaoutputdevices}" -eq "1" ]; then
	## multiple outputdevices detected
        ## ask the user to choose one of them
	echo -e "\nEnter the hardware address of the alsa output device to test"
	alsadevicelabel="$(read -e -p "(press ENTER to select the default): " \
 -i "${defaultcard}" alsadev && echo $alsadev)"
    else
	alsadevicelabel="${defaultcard}"
    fi

    ## test whether the device is not in use by other programs
    alsabusy="$(cat /dev/urandom | \
LANG=C aplay -D ${alsadevicelabel} 2>&1 >/dev/null | \
grep busy)"
    
    if [ ! "$?" -eq "0" ]; then
    ## query the selected alsa playback device for supported formats
    ## `--dump-hw-params' in alsa-utils 1.0.27, Debian Wheezy = 1.0.25
	
	alsaformats="$(cat /dev/urandom | \
LANG=C aplay -D ${alsadevicelabel} 2>&1 >/dev/null | \
grep '^-' | sed 's/^- //g' )"
	    
	echo -e "\nThe selected alsa output device ${alsadevicelabel} \
supports the following \ndigital audio formats:"

	index=0
	while read -r line; do
	    let index+=1
	    echo -e "${index}) ${line}"
	done <<< "${alsaformats}"
    else
	echo -e "\nError: Could not determine the supported digital \
formats for ${alsadevicelabel} \n       because it is in use ..."
	return 1
    fi

}


if [[ -f ${paconf} ]]; then

    pulsedisable
    alsadetect
    pulserestoreconf
else
    alsadetect
fi

