#!/usr/bin/env bash

## script to list alsa digital output devices by hardware address
## and the digital audio (output) formats they support
##
## source:    https://github.com/ronalde/mpd-configure
## also see:  http://lacocina.nl/2013/04/19/alsa-highres/

MPD_HOST="localhost"
MPD_PORT="6600"

CMD_TELNET="$(which telnet)"
PA_CLIENTCONF_FILE=~/.pulse/client.conf
PA_CLIENTCONF_PRESENT="$([[ -f ${PA_CLIENTCONF_FILE} ]])"
PA_CLIENT_CONF_BACKUP="${PA_CLIENT_CONF}.da-backup"
PA_CONF_RESTORE="false"
PA_CONF_CREATED="false"

ALSA_OUTPUT_DEVICES=0
PROC_ASOUND="/proc/asound"
PROC_USB_STREAM=""

echo -e "conf present: ${PA_CLIENTCONF_PRESENT}"
## array to store all alsa hw:x,y addresses
declare -a ALSA_HW_ADDRESSES=()
SELECTED_HW_ADDRESS=""

LANG=C


echo_stderr() {
    echo -e "$@" 1>&2; 
}

die() {
    echo_stderr "\nError: $@"
    exit 1
}

inform() {
    echo_stderr "$@"
}

debug() {
    echo_stderr "DEBUG *** $@"
}


pulserestoreconf() {
    ## restores pulseaudio client configuration to state before running
    ## this script

    if [ "${PA_CONF_CREATED}" == "true" ]; then
	## conf file was created by this script; remove it
	rm "${PA_CLIENTCONF_FILE}"
    else
	if [ "${PA_CONF_RESTORE}" == "true" ]; then
	    ## restore existing conf file
	    mv "${PA_CLIENT_CONF_BACKUP}" "${PA_CLIENTCONF_FILE}"
	fi
    fi
}

pulsebackupconf() {
    ## remove existing backup file of pulseaudio client configuration
    ## created by script

    ## clean up from previous attempts
    [[ -f "${PA_CLIENT_CONF_BACKUP}" ]] && rm "${PA_CLIENT_CONF_BACKUP}"

    cp "${PA_CLIENTCONF_FILE}" "${PA_CLIENT_CONF_BACKUP}"

}


pulsedisable() {
    ## detects if pulseaudio is running and if os, temporary disables
    ## and kills it

    ## check if pulseaudio is running for the current user
    parunning="$(pgrep -u ${USER} pulseaudio)"

    if [ ! "$?" -eq "1" ]; then
	inform "pulseaudio is running; will temporary disable and stop it ..."
    	
        # temporary disable pulseaudio
	if [ -f "${PA_CLIENTCONF_FILE}" ] ; then
	    pulsebackupconf
	    if [ "$?" -eq "0" ]; then
		sed -i 's/autospawn[[:space:]]*=[[:space:]]*\([no]*\)/autospawn = no/gI' ${PA_CLIENTCONF_FILE} 
		paconfrestore="true"
	    fi
	else
	    echo "autospawn = no" > "${PA_CLIENTCONF_FILE}"
	    paconfcreated="true"
	fi
	
        ## kill pulseaudio
	pulseaudio --kill

	## check if that worked
	pakillok="$(pgrep -u ${USER} pulseaudio)"

	if [ "$?" = "0" ] ; then
	    ## pulse is still running
	    pulserestoreconf
	    die "Could not kill pulseaudio."
	fi
    fi
}

fetch_alsadevices_list() {
    ## displays/returns a formatted list of alsa cards, each with its
    ## digital output(s)

    MSG_NODIGITAL_OUTPUTS="No alsa cards with digital outputs found."

    cmd_output=""
    
    ## construct list of alsa digital outputs
    aplay_output="$(aplay -l | grep ^card | grep -i -E 'usb|digital|hdmi|i2s|spdif|toslink|adat')"

    [[ -z "${aplay_output}" ]] && die "${MSG_NODIGITAL_OUTPUTS}"

    ## loop through each line of aplay output   
    while read -r line; do

	if [[ "${line}" =~ "card "([0-9]*)": "(.*)" ["(.*)"], device "([0-9]*)": "(.*)" ["(.*)"]"(.*) ]]; then
	    let ALSA_OUTPUT_DEVICES+=1
	    cardnr="${BASH_REMATCH[1]}"
	    cardname="${BASH_REMATCH[2]}"
	    cardlabel="${BASH_REMATCH[3]}"
	    devnr="${BASH_REMATCH[4]}"
	    devname="${BASH_REMATCH[5]}"
	    devlabel="${BASH_REMATCH[6]}"
	    hw_address="hw:${cardnr},${devnr}"

	    ## add the hardware address to the array
	    ALSA_HW_ADDRESSES=("${ALSA_HW_ADDRESSES[@]}" "${hw_address}")
 
	    cmd_output=$(echo -e "${cmd_output} ${ALSA_OUTPUT_DEVICES}) ${hw_address} (Card \"${cardlabel}\" with output device \"${devlabel}\")")
	    cmd_output="${cmd_output}\n"

	fi

    done <<< "${aplay_output}"

    [[ ${#ALSA_HW_ADDRESSES[@]} -gt 1 ]] && DEVS="s"
    inform "\nDetected alsa device${DEVS} with digital output${DEVS}:"

    ## display/return the cards found
    echo -e "${cmd_output}"
    
    select_hw_address

}

pop_hw_address() {
    ## pop the hw_address specified by $1 from the array
    ## rerun hw_address as long as the array is not empty

    hw_address="$1"
    declare -a ALSA_HW_ADDRESSES=( ${ALSA_HW_ADDRESSES[@]/${hw_address}/} )
    if [ ${#ALSA_HW_ADDRESSES[@]} -gt 0 ]; then
	select_hw_address
    fi
}

select_hw_address() {
    ## select a hardware address from the array. When there's mpre
    ## than one device, prompts the user which one to examine,
    ## otherwise select it by default

    MSG_SELECT_ALSADEV="\nEnter the hardware address of the alsa output device to test"
    MSG_ENTER_DEFAULT="and press [ENTER] to select the default: "

    if [ "${#ALSA_HW_ADDRESSES[@]}" = "1" ]; then
	SELECTED_HW_ADDRESS="${ALSA_HW_ADDRESSES[0]}"
	inform "\n"
	read -p "Press [ENTER] to probe device \`${SELECTED_HW_ADDRESS}' ..."
	list_alsa_output_formats
	detect_stream
    else
	inform "${MSG_SELECT_ALSADEV}"
	SELECTED_HW_ADDRESS="$(read -e -p "${MSG_ENTER_DEFAULT}" -i "${ALSA_HW_ADDRESSES[0]}" alsadev && echo ${alsadev})"
	list_alsa_output_formats
	detect_stream
	pop_hw_address "${SELECTED_HW_ADDRESS}"
    fi
    
}


list_alsa_output_formats() {
    ## list digital output devices for selected alsa card with their
    ## hw:x,y address
    
    ## test whether the device is not in use by other programs
    alsabusy="$(cat /dev/urandom | \
LANG=C aplay -D ${SELECTED_HW_ADDRESS} 2>&1 >/dev/null | \
grep busy)"
    
    if [ ! "$?" -eq "0" ]; then
    ## query the selected alsa playback device for supported formats
    ## `--dump-hw-params' in alsa-utils 1.0.27, Debian Wheezy = 1.0.25
	
	alsaformats="$(cat /dev/urandom | \
LANG=C aplay -D ${SELECTED_HW_ADDRESS} 2>&1 >/dev/null | \
grep '^-' | sed 's/^- //g' )"
	    
	inform "\n\`${SELECTED_HW_ADDRESS}' supports the following digital audio formats:"

	index=0
	while read -r line; do
	    let index+=1
	    echo -e " ${index}) ${line}"
	done <<< "${alsaformats}"
    else
	## construct the path to the device node (ie `/dev/snd/pcmCxDyp`)
	dev_snd_device="$(echo -e "${SELECTED_HW_ADDRESS}" | sed "s#hw:\([0-9]*\),\([0-9]*\)#/dev/snd/pcmC\1D\2p#")"
	lsof_out="$(lsof -F c ${dev_snd_device})"
	p_name="$(echo -e "${lsof_out}" | grep ^c | sed 's/^c\(.*\)$/\1/')"
	p_id="$(echo -e "${lsof_out}" | grep ^p | sed 's/^p\(.*\)$/\1/')"
	if [ "${p_name}" = "mpd" ]; then
	    inform "NOTICE: Could not determine the supported digital formats for \
\`${SELECTED_HW_ADDRESS}' \nbecause it is in use by mpd. You might want to pause mpd\
\nusing your favourite mpd client and rerun this script."
	else
	    inform "NOTICE: Could not determine the supported digital formats for \
\n\`${SELECTED_HW_ADDRESS}' because it is in use by \`${p_name}' with process id \`${p_id}'."
	fi
	return 1
    fi

}


detect_stream() {
    ## map the selected sound card to the appropriate 
    ## USB audio class stream file in
    ## /proc/asound/cardX/streamY

    MSG_NO_STREAM="Unable to monitor changed modes of device"
    MSG_NO_UACMODULE="\nModule \`snd_usb_audio' not loaded; therefore no USB audio class \
\ndevices are present.${MSG_NO_STREAM}"
    MSG_NO_UACCARD="\n${MSG_NO_STREAM} \`${SELECTED_HW_ADDRESS}', because it is \
\nnot a USB audio class device."

    Q_WATCH_STREAM="\nPress [ENTER] when you want to monitor the stream "
    Q_WATCH_INSTRUCT="\nreact when playing different digital audio formats using your mpd client.\n "
    Q_BREAK_WATCH="Press [CTRL+C] to quit or exit the \`watch' screen ."

    ## detect if module snd_usb_audio is loaded
    if [ "$(lsmod | grep snd_usb_audio)" ]; then
	defusbstream="$(echo -e "${SELECTED_HW_ADDRESS}" | \
sed "s#hw:\([0-9]*\),\([0-9]*\)#${PROC_ASOUND}/card\1/stream\2#")"

	if [ -f "${defusbstream}" ]; then
	    inform "${Q_WATCH_STREAM}\`${defusbstream}'${Q_WATCH_INSTRUCT}"
	    read -p "${Q_BREAK_WATCH}" 
	    watch -n 0.1 cat ${defusbstream}
	else
	    ## UAC module loaded but selected card is not a UAC device
	    inform "${MSG_NO_UACCARD}"
	    #select_hw_address
	fi
    else
	inform "${MSG_NO_UACMODULE}"
    fi

}


## main


if [[ -f ${PA_CLIENTCONF_FILE} ]]; then

    pulsedisable
    #list_alsa_output_formats
    ## fetch list with alsa cards and outputs
    fetch_alsadevices_list

    ## if multiple output devices were detected list them and
    ## ask the user to choose the one to use
    # select_hw_address

    pulserestoreconf
else
    #list_alsa_output_formats
    fetch_alsadevices_list

    ## if multiple output devices were detected list them and
    ## ask the user to choose the one to use
fi

#detect_stream
