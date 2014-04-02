#!/usr/bin/env bash

## script to list alsa digital output devices by hardware address
## and the digital audio (output) formats they support
##
## source:    https://github.com/ronalde/mpd-configure
## also see:  http://lacocina.nl/detect-alsa-output-capabilities

## space seperated list of output devices that will be filtered for 
APLAY_OUTPUT_FILTER="usb digital hdmi i2s spdif toslink adat uac"

PA_CLIENTCONF_FILE=~/.pulse/client.conf
PA_CLIENT_CONF_BACKUP="${PA_CLIENT_CONF}.da-backup"
PA_CONF_RESTORE="false"
PA_CONF_CREATED="false"

PROP_NOT_APPLICABLE="n/a"
MSG_DEVICE_BUSY="can't detect"

## array to store all alsa hw:x,y addresses
declare -a ALSA_UAC_DEVICES=()

LANG=C
#DEBUG="true"

echo_stderr() {
    echo -e "$@" 1>&2; 
}

die() {
    echo_stderr "\nError: $@"
    pulse_restoreconf
    exit 1
}

inform() {
    echo_stderr "$@"
}

debug() {
    echo_stderr "DEBUG *** $@"
}


pulse_restoreconf() {
    ## restores pulseaudio client configuration to state before running
    ## this script

    [[ ! -z "${DEBUG}" ]] && debug "entering \`${FUNCNAME}' with arguments \`$@'"

    if [ "${PA_CONF_CREATED}" = "true" ]; then
	## conf file was created by this script; remove it
	rm "${PA_CLIENTCONF_FILE}"
    else
	if [ "${PA_CONF_RESTORE}" = "true" ]; then
	    ## restore existing conf file
	    mv "${PA_CLIENT_CONF_BACKUP}" "${PA_CLIENTCONF_FILE}"
	fi
    fi
}

pulse_backupconf() {
    ## remove existing backup file of pulseaudio client configuration
    ## created by script

    [[ ! -z "${DEBUG}" ]] && debug "entering \`${FUNCNAME}' with arguments \`$@'"

    ## clean up from previous attempts
    [[ -f "${PA_CLIENT_CONF_BACKUP}" ]] && rm "${PA_CLIENT_CONF_BACKUP}"

    cp "${PA_CLIENTCONF_FILE}" "${PA_CLIENT_CONF_BACKUP}"

}


pulse_disable() {
    ## detects if pulseaudio is running and if os, temporary disables
    ## and kills it

    [[ ! -z "${DEBUG}" ]] && debug "entering \`${FUNCNAME}' with arguments \`$@'"

    ## check if pulseaudio is running for the current user
    parunning="$(pgrep -u ${USER} pulseaudio)"

    if [ ! "$?" -eq "1" ]; then
	inform "pulseaudio is running; will temporary disable and stop it ..."

        # temporary disable pulseaudio
	if [ -f "${PA_CLIENTCONF_FILE}" ] ; then
	    pulse_backupconf
	    if [ "$?" -eq "0" ]; then
		sed -i 's/autospawn[[:space:]]*=[[:space:]]*\([no]*\)/autospawn = no/gI' ${PA_CLIENTCONF_FILE} 
		PA_CONF_RESTORE="true"
	    fi
	else
	    echo "autospawn = no" > "${PA_CLIENTCONF_FILE}"
	    PA_CONF_CREATED="true"
	fi
	
        ## kill pulseaudio
	pulseaudio --kill

	## check if that worked
#	pakillok="$(pgrep -u ${USER} pulseaudio)"

	if [ "$?" = "1" ] ; then
	    ## pulse is still running
	    die "Could not kill pulseaudio."
	fi
    fi
}

fetch_alsadevices_list() {
    ## displays/returns a formatted list of alsa cards, each with its
    ## digital output(s) and capabilities

    [[ ! -z "${DEBUG}" ]] && debug "entering \`${FUNCNAME}' with arguments \`$@'"

    MSG_NODIGITAL_OUTPUTS="No alsa cards with digital outputs found."

    ## put labels for output in array
    declare -a LST_PROPS=(\
"   - hardware address =  " \
"   - character device =  " \
"   - digital formats  =  " \
"   - usb audio class  =  " \
"   - stream file      =  ")


    cmd_output=""
    alsa_dev_no=0    

    ## construct list of alsa digital outputs
    aplay_output="$(${CMD_APLAY} -l | \
grep ^card | \
grep -i -E "${APLAY_OUTPUT_FILTER// /|}")"

    [[ -z "${aplay_output}" ]] && die "${MSG_NODIGITAL_OUTPUTS}"

    ## loop through each line of aplay output   
    while read -r line; do

	if [[ "${line}" =~ "card "([0-9]*)": "(.*)" ["(.*)"], device "([0-9]*)": "(.*)" ["(.*)"]"(.*) ]]; then
	    let alsa_dev_no+=1
	    cardnr="${BASH_REMATCH[1]}"
	    cardname="${BASH_REMATCH[2]}"
	    cardlabel="${BASH_REMATCH[3]}"
	    devnr="${BASH_REMATCH[4]}"
	    devname="${BASH_REMATCH[5]}"
	    devlabel="${BASH_REMATCH[6]}"
	    hw_address="hw:${cardnr},${devnr}"

	    chardev="$(return_alsa_chardev "${hw_address}")"
	    formats="$(return_alsa_formats "${hw_address}")"
	    if [ "${formats}" = "${MSG_DEVICE_BUSY}" ]; then
		msg_in_use="$(alsa_device_busy "${chardev}")"
		formats="(${MSG_DEVICE_BUSY}: ${msg_in_use})"
	    fi
	    streamfile="$(return_alsa_streamfile "${hw_address}")"
	    if [ ! "${streamfile}" = "${PROP_NOT_APPLICABLE}" ]; then
		uacclass="$(return_alsa_uacclass "${streamfile}")"
		ALSA_UAC_DEVICES+=("${hw_address}")
	    else
		uacclass="${PROP_NOT_APPLICABLE}"
	    fi

	    card_label=" ${alsa_dev_no}) Card \`${cardlabel}' using output \`${devlabel}':"
	 	    
	    ## display the results
	    cat <<EOF

${card_label}
${LST_PROPS[0]}${hw_address}
${LST_PROPS[1]}${chardev}
${LST_PROPS[2]}${formats}
${LST_PROPS[3]}${uacclass}
${LST_PROPS[4]}${streamfile}
EOF

	fi

    done <<< "${aplay_output}"

    ## messages in case of no, single or multiple uac devices
    IFS='' read -r -d '' msg_no_uac <<'EOF' 

    * No usb audio class devices found, will now exit
EOF

    IFS='' read -r -d '' msg_single_uac <<'EOF'

   * Start watching the stream file by pressing [ENTER].
   * [CTRL+C] can be used to quit now and to exit the watch screen.
EOF

    IFS='' read -r -d '' msg_multiple_uacs <<'EOF'

   Specify the device you want to monitor below or accept the
   default:
   * start watching the stream file by pressing [ENTER]. 
   * [CTRL+C] can be used to quit now and to exit the watch screen.
EOF

    case ${#ALSA_UAC_DEVICES[@]} in 
	"0")
	    inform "${msg_no_uac}"
	    pulse_restoreconf
	    exit 0
	    ;;
	"1")
	    inform "${msg_single_uac}"
	    ;;
	*)
	    inform "${msg_multiple_uacs}"
	    ;;
    esac

    prompt="   > Device to watch: "
    DEFAULT_UAC="${ALSA_UAC_DEVICES[0]}"
    UAC_DEVICE="$(read -e -p "${prompt}" \
-i "${DEFAULT_UAC}" UAC_DEVICE && \
echo -e "${UAC_DEVICE}")"
    ${CMD_WATCH} -n 0.1 cat $(return_alsa_streamfile "${UAC_DEVICE}")

}


alsa_device_busy() {
    ## looks for and returns processes that have exclusive access to
    ## chardev $1

    alsa_chardev="$1"

    lsof_out="$(lsof -F c ${alsa_chardev})"
    p_name="$(echo -e "${lsof_out}" | grep ^c | sed 's/^c\(.*\)$/\1/')"
    p_id="$(echo -e "${lsof_out}" | grep ^p | sed 's/^p\(.*\)$/\1/')"
    echo -e "in use by \`${p_name}' with pid \`${p_id}'"
}

return_alsa_formats() {
    ## fetches and returns a comma seperated string of playback formats
    ## by feeding it dummy input while keeping the test silent 
    ## by redirecting output to /dev/null.
    ## 
    ## needs address of alsa output device in `hw:x,y' format 
    ## as single argument ($1)

    [[ ! -z "${DEBUG}" ]] && debug "entering \`${FUNCNAME}' with arguments \`$@'"

    alsa_hw_device="$1"

    alsaformats="$(cat /dev/urandom | \
LANG=C ${CMD_APLAY} -D ${alsa_hw_device} 2>&1 >/dev/null | \
grep '^-' | sed ':a;N;$!ba;s/\n-/,/g' | sed 's/^- //' )"

    [[ ! -z "${alsaformats}" ]] && \
	echo -e "${alsaformats}" || \
	echo -e "${MSG_DEVICE_BUSY}"

}

return_alsa_chardev() {
    ## constructs, tests and returns the path to node in /dev.
    ## 
    ## needs address of alsa output device in `hw:x,y' format 
    ## as single argument ($1)

    [[ ! -z "${DEBUG}" ]] && debug "entering \`${FUNCNAME}' with arguments \`$@'"

    alsa_hw_device="$1"

    alsa_chardev="$(echo -e "${alsa_hw_device}" | \
sed "s#hw:\([0-9]*\),\([0-9]*\)#/dev/snd/pcmC\1D\2p#")"
    [[ -c "${alsa_chardev}" ]] && echo -e "${alsa_chardev}"

}


return_alsa_streamfile() {
    ## constructs, tests and returns the path to the stream file in
    ## /proc and fills the ALSA_UAC_DEVICES array.
    ## 
    ## needs address of alsa output device in `hw:x,y' format 
    ## as single argument ($1)

    [[ ! -z "${DEBUG}" ]] && debug "entering \`${FUNCNAME}' with arguments \`$@'"

    alsa_hw_device="$1"

    if [ "$(lsmod | grep snd_usb_audio)" ]; then
	alsa_streamfile="$(echo -e "${alsa_hw_device}" | \
sed "s#hw:\([0-9]*\),\([0-9]*\)#/proc/asound/card\1/stream\2#")"
	[[ -f "${alsa_streamfile}" ]] && \
	    echo -e "${alsa_streamfile}" || \
	    echo -e "${PROP_NOT_APPLICABLE}"
    else
	echo -e "${PROP_NOT_APPLICABLE}"
    fi

}


return_alsa_uacclass() {
    ## returns the usb audio class.
    ## 
    ## needs path to stream file as single argument ($1)

    [[ ! -z "${DEBUG}" ]] && debug "entering \`${FUNCNAME}' with arguments \`$@'"

    alsa_streamfile="$1"
    
    endpoint_filter="Endpoint: [0-9] OUT"
    declare -a endpoints=( "ADAPTIVE" "ASYNC")
    declare -a class_labels=( "1: isochronous adaptive" "2: isochronous asynchronous")
    
    alsa_uacclass="$(grep -E "${endpoint_filter}" "${alsa_streamfile}" | sed "s/${endpoint_filter} (\(.*\))$/\1/" | sed 's/ //g')"
    [[ "${endpoints[0]}" == "${alsa_uacclass}" ]] && \
	echo -e "${class_labels[0]}" || \
	echo -e "${class_labels[1]}"

}



command_not_found() {
    ## give installation instructions when a command is not available

    command="$1"
    package="$2"
    instructions="$3"
    msg="Error: command \`${command}' not found. "
    if [ -z "${instructions}" ]; then
	msg+="Users of Debian (or deratives, like Ubuntu) can install it with:\n"
	msg+=" sudo apt-get install ${package}"
    else
	msg+="${instructions}"
    fi
    die "${msg}"

}


### main

## check if needed commands are available
CMD_APLAY=$(which aplay || command_not_found "aplay" "alsa-utils")
CMD_WATCH=$(which watch || command_not_found "watch" "procps")

## temporary stop and disable pulseaudio if its running
pulse_disable

## fetch list with alsa cards and outputs
fetch_alsadevices_list

## restore pulse to state before running the script
pulse_restoreconf

### done