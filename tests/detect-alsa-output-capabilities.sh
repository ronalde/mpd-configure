#!/usr/bin/env bash

## script to list alsa digital output devices by hardware address
## and the digital audio (output) formats they support
##
##  Copyright (C) 2014 Ronald van Engelen <ronalde+github@lacocina.nl>
##  This program is free software: you can redistribute it and/or modify
##  it under the terms of the GNU General Public License as published by
##  the Free Software Foundation, either version 3 of the License, or
##  (at your option) any later version.
##
##  This program is distributed in the hope that it will be useful,
##  but WITHOUT ANY WARRANTY; without even the implied warranty of
##  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
##  GNU General Public License for more details.
##
##  You should have received a copy of the GNU General Public License
##  along with this program.  If not, see <http://www.gnu.org/licenses/>.
##
## source:    https://github.com/ronalde/mpd-configure
## also see:  http://lacocina.nl/detect-alsa-output-capabilities


## space seperated list of output devices that will be filtered for
APLAY_OUTPUT_FILTER="usb digital hdmi i2s spdif toslink adat uac"

## default filename for user settings for pulseaudio
PA_CLIENTCONF_FILE=~/.pulse/client.conf
## file name of the backup which the script can create
PA_CLIENT_CONF_BACKUP="${PA_CLIENT_CONF}.da-backup"
PA_CONF_RESTORE="false"
PA_CONF_CREATED="false"

PROP_NOT_APPLICABLE="n/a"
MSG_DEVICE_BUSY="can't detect"

## array to store pairs of hardware address (hw:x,y) and its stream
## file (in /proc/asound)
declare -A ALSA_UAC_DEVICES
## and store the hardware addresses in a simple
## indexed array for retrieving the default
declare -a ALSA_UAC_INDEXES=()

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

    if [[ "${PA_CONF_CREATED}" = "true" ]]; then
	## conf file was created by this script; remove it
	rm "${PA_CLIENTCONF_FILE}"
    else
	if [[ "${PA_CONF_RESTORE}" = "true" ]]; then
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

    if [[ ! "$?" -eq "1" ]]; then
	inform "pulseaudio is running; will temporary disable and stop it ..."

        # temporary disable pulseaudio
	if [[ -f "${PA_CLIENTCONF_FILE}" ]] ; then
	    pulse_backupconf
	    if [[ "$?" -eq "0" ]]; then
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

	if [[ "$?" = "1" ]] ; then
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
	    if [[ "${formats}" = "${MSG_DEVICE_BUSY}" ]]; then
		msg_in_use="$(alsa_device_busy "${chardev}")"
		formats="(${MSG_DEVICE_BUSY}: ${msg_in_use})"
	    fi
	    streamfile="$(return_alsa_streamfile "${hw_address}")"
	    if [[ ! "${streamfile}" = "${PROP_NOT_APPLICABLE}" ]]; then
		uacclass="$(return_alsa_uacclass "${streamfile}")"
		ALSA_UAC_DEVICES+=(["${hw_address}"]="${streamfile}")
		ALSA_UAC_INDEXES+=("${hw_address}")
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

    ## prompt the user to select a hardware address in order to watch
    ## its associated stream file in /proc/asound, defaults to the
    ## first uac device found.
    prompt="   > Device to watch: "
    default_hw_address="${ALSA_UAC_INDEXES[0]}"
    UAC_DEVICE="$(read -e -p "${prompt}" \
-i "${default_hw_address}" UAC_DEVICE && \
echo -e "${UAC_DEVICE}")"

    ${CMD_WATCH} -n 0.1 cat "${ALSA_UAC_DEVICES[${UAC_DEVICE}]}"

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

    if [[ "$(lsmod | grep snd_usb_audio)" ]]; then
	alsa_streamfile="$(echo -e "${alsa_hw_device}" | \
sed "s#hw:\([0-9]*\),\([0-9]*\)#/proc/asound/card\1/stream\2#")"
	[[ -f "${alsa_streamfile}" ]] && \
	    echo -e "${alsa_streamfile}" || \
	    echo -e "${PROP_NOT_APPLICABLE}"
    else
	echo -e "${PROP_NOT_APPLICABLE}"
    fi

}


function return_alsa_uacclass() {
    ## returns/echoes the usb audio class with a description.
    ## needs path to stream file as single argument ($1)

    [[ ! -z "${DEBUG}" ]] && debug "entering \`${FUNCNAME}' with arguments \`$@'"

    alsa_streamfile_path="$1"

    ## store the contents of the stream file in an array
    mapfile < "${alsa_streamfile_path}" alsa_streamfile_contents
    ## expand the array 
    alsa_streamfile_expanded=$(printf "%s" "${alsa_streamfile_contents[@]}")

    ## part of begin of the protion of the line we're looking for (re)
    ep_base="Endpoint: [3,5] OUT ("
    ## the end of that portion
    ep_end=")"

    ## the portion we need ending with ep_end
    ep_matched_portion="${alsa_streamfile_expanded#*${ep_base}}"
    ## the portion without ep_end
    ep_mode="${ep_matched_portion/)*/}"

    ## strings alsa uses for endpoint descriptors
    endpoint_adapt="ADAPTIVE"
    endpoint_async="ASYNC"

    ## store a pair of alsa endpoint descriptors/display labels
    ## containing the usb audio class
    declare -A endpoints=( \
	["${endpoint_adapt}"]="1: isochronous adaptive" \
	["${endpoint_async}"]="2: isochronous asynchronous" \
	)

    ## test if the filtered endpoint is adaptive/async and return/echo
    ## its display label
    [[ "${ep_mode}" = "${endpoints[${endpoint_adapt}]}" ]] && \
	echo -e "${endpoints[${endpoint_adapt}]}" || \
	echo -e "${endpoints[${endpoint_async}]}"

}


command_not_found() {
    ## give installation instructions for package $2 when command $1
    ## is not available, optional with non default instructions $3
    ## and exit with error

    command="$1"
    package="$2"
    instructions="$3"
    msg="Error: command \`${command}' not found. "
    if [[ -z "${instructions}" ]]; then
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