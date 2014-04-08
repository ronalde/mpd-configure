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


## space seperated list strings the available alsa output devices will
## be filtered for
APLAY_OUTPUT_FILTER="usb uac dsd digital hdmi i2s spdif toslink adat \
iec958"

## default filename for user settings for pulseaudio
PA_CLIENTCONF_FILE=${HOME}/.pulse/client.conf
## file name of the backup which the script can create
PA_CLIENT_CONF_BACKUP="${PA_CLIENT_CONF}.da-backup"
PA_CONF_RESTORE=""
PA_CONF_CREATED=""
PA_KILLED=""

PROP_NOT_APPLICABLE="(n/a)"
MSG_DEVICE_BUSY="can't detect"
MSG_RUN_AS_ROOT="device in use, run as root to display process."
MSG_NO_DEVICE="no such device"
MSG_NO_FILE="no such file"

MSG_PA_RUNNING=" - pulseaudio is running; will temporary disable and stop it ..."
MSG_PA_CONF_RESTORED="\n - pulseaudio configuration restored."
MSG_PA_RESTARTED_BYSCRIPT=" - pulseaudio restarted by script."
MSG_PA_RESTARTED_BYSESSION=" - pulseaudio restarted by session."

MSG_TAB=" * "

ALSA_DO_IF="digital audio output interface"
ALSA_DO_UAC="USB Audio Class (UAC)"
ALSA_DO_NONUAC="non-UAC"

MSG_MATCH_DO_NONE="No ${ALSA_DO_IF}s found."
MSG_MATCH_DO_SINGLE="One ${ALSA_DO_IF} found."
MSG_MATCH_DO_MULTIPLE="Multiple ${ALSA_DO_IF}s found."

MSG_MATCH_NONUACDO_SINGLE="One ${ALSA_DO_NONUAC} ${ALSA_DO_IF} found."
MSG_MATCH_NONUACDO_MULTIPLE="Multiple ${ALSA_DO_NONUAC} ${ALSA_DO_IF}s found."

MSG_MATCH_UACDO_NONE="No ${ALSA_DO_UAC} ${ALSA_DO_IF}s found."
MSG_MATCH_UACDO_SINGLE="One ${ALSA_DO_UAC} ${ALSA_DO_IF} found."
MSG_MATCH_UACDO_MULTIPLE="Multiple ${ALSA_DO_UAC} ${ALSA_DO_IF}s found."

MSG_WATCH_PROMPT=" Hardware address of ${ALSA_DO_IF} > "
MSG_SUMMARY=" Summary:\n"

IFS='' read -r -d '' MSG_WATCH_SINGLE <<'EOF'

 Start monitoring the interface by pressing [ENTER].
  - [CTRL+C] can be used to quit now and to exit the watch screen.
EOF
IFS='' read -r -d '' MSG_WATCH_MULTIPLE <<'EOF'

 Specify the hardware address of the interface to monitor below:
  - Press [ENTER] to start monitoring that interface.
  - Press [CTRL+C] to quit now or to exit the screen while monitoring.
EOF

## declarative arrays to store pairs of hardware address (hw:x,y) and
## its hw_params file (in `/proc/asound') for all devices with digital out (DO)
## and its stream file for UAC devices
declare -A ALSA_DO_DEVICES
declare -A ALSA_UAC_DEVICES
## indexed array to store the hardware addresses for retrieving the
## defaults
declare -a ALSA_DO_INDEXES=()
declare -a ALSA_UAC_INDEXES=()

LANG=C
#DEBUG="true"

### generic functions
function echo_stderr() {
    echo -e "$@" 1>&2; 
}

function die() {
    echo_stderr "\nError: $@"
    pulse_restoreconf
    exit 1
}

function inform() {
    echo_stderr "$@"
}

function debug() {
    echo_stderr "DEBUG *** $@"
}

function command_not_found() {
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

### functions specific for managing pulseaudio

function pulse_restoreconf() {
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
	    inform "${MSG_PA_CONF_RESTORED}"
	fi
    fi

    ## restart pulseaudio if script killed it before and it is not
    ## restarted by the users desktop session
    if [[ ! -z "${PA_KILLED}" ]]; then
	    parunning="$(pgrep -u ${USER} pulseaudio)"
	    if [[ "$?" -eq "1" ]]; then
		pulseaudio
		inform "${MSG_PA_RESTARTED_BYSCRIPT}"
	    fi
	    inform "${MSG_PA_RESTARTED_BYSESSION}"
    fi
}

function pulse_backupconf() {
    ## remove existing backup file of pulseaudio client configuration
    ## created by script

    [[ ! -z "${DEBUG}" ]] && debug "entering \`${FUNCNAME}' with arguments \`$@'"

    ## clean up from previous attempts
    [[ -f "${PA_CLIENT_CONF_BACKUP}" ]] && rm "${PA_CLIENT_CONF_BACKUP}"

    cp "${PA_CLIENTCONF_FILE}" "${PA_CLIENT_CONF_BACKUP}"

}


function pulse_disable() {
    ## detects if pulseaudio is running and if os, temporary disables
    ## and kills it

    [[ ! -z "${DEBUG}" ]] && debug "entering \`${FUNCNAME}' with arguments \`$@'"

    ## check if pulseaudio is running for the current user
    parunning="$(pgrep -u ${USER} pulseaudio)"

    if [[ ! "$?" -eq "1" ]]; then
	inform "${MSG_PA_RUNNING}"

        ## temporary disable pulseaudio
	if [[ -f "${PA_CLIENTCONF_FILE}" ]] ; then
	    ## user has an existing conf file; back it up
	    pulse_backupconf
	    if [[ "$?" -eq "0" ]]; then
		## backup was succesful, now modify the conf file
		sed -i 's/autospawn[[:space:]]*=[[:space:]]*\([no]*\)/autospawn = no/gI' \
		    "${PA_CLIENTCONF_FILE}"
		PA_CONF_RESTORE="true"
	    fi
	else
	    ## no existing conf file; create a new one
	    echo "autospawn = no" > "${PA_CLIENTCONF_FILE}"
	    PA_CONF_CREATED="true"
	fi
	
        ## try to kill pulseaudio; otherwise exit with error
	pulseaudio --kill
	if [[ "$?" = "1" ]] ; then
	    ## pulse is still running
	    die "Could not kill pulseaudio."
	else
	    PA_KILLED="True"
	fi
    fi
}

### alsa related functions

function fetch_alsadevices_list() {
    ## displays/returns a formatted list of alsa cards, each with its
    ## digital output(s) and capabilities

    [[ ! -z "${DEBUG}" ]] && debug "entering \`${FUNCNAME}' with arguments \`$@'"

    cmd_output=""
    alsa_dev_no=0    

    ## construct list of alsa digital outputs
    aplay_output="$(${CMD_APLAY} -l | \
grep ^card | \
grep -i -E "${APLAY_OUTPUT_FILTER// /|}")"

    ## exit if no digital interfaces where found
    [[ -z "${aplay_output}" ]] && die "\n${MSG_TAB}${MSG_MATCH_DO_NONE}\n"

    ## loop through each line of aplay output   
    while read -r line; do

	## construct batch rematch (brm) regexp for card portion (ie before `,')
	brm_card="card[[:space:]]([0-99]):[[:space:]](.*)[[:space:]]\[(.*)\]"
	## same for device portion
	brm_dev="[[:space:]]device[[:space:]]([0-99]):[[:space:]](.*)[[:space:]]\[(.*)\](.*)"
	## put together
	brm_template="${brm_card},${brm_dev}"

	## start matching
	if [[ "${line}" =~ ${brm_template} ]]; then
	    let alsa_dev_no+=1
	    cardnr="${BASH_REMATCH[1]}"
	    cardname="${BASH_REMATCH[2]}"
	    cardlabel="${BASH_REMATCH[3]}"
	    devnr="${BASH_REMATCH[4]}"
	    devname="${BASH_REMATCH[5]}"
	    devlabel="${BASH_REMATCH[6]}"
	    hw_address="hw:${cardnr},${devnr}"

	    chardev="$(return_alsa_chardev "${cardnr}" "${devnr}")"
	    formats="$(return_alsa_formats "${hw_address}")"
	    if [[ "${formats}" = "${MSG_DEVICE_BUSY}" ]]; then
		msg_in_use="$(alsa_device_busy "${chardev}")"
		formats="(${MSG_DEVICE_BUSY}: ${msg_in_use})"
	    fi
	    streamfile="$(return_alsa_streamfile "${cardnr}" "${devnr}")"
	    if [[ ! "${streamfile}" = "${PROP_NOT_APPLICABLE}" ]]; then
		uacclass="$(return_alsa_uacclass "${streamfile}")"
		ALSA_UAC_DEVICES+=(["${hw_address}"]="${streamfile}")
		ALSA_UAC_INDEXES+=("${hw_address}")
	    else
		uacclass="${PROP_NOT_APPLICABLE}"
	    fi

	    hwparamsfile="$(return_alsa_hwparamsfile "${cardnr}" "${devnr}")"
	    ALSA_DO_DEVICES+=(["${hw_address}"]="${hwparamsfile}")
	    ALSA_DO_INDEXES+=("${hw_address}")

	    card_display_title=" ${alsa_dev_no}) ${ALSA_DO_IF/digital/Digital} \`${hw_address}'"
	    card_display_label="Card \`${cardlabel}' using output \`${devlabel}'"

	    ## put labels for output in indexed array
	    declare -a LST_PROPS=(\
"   - soundcard        =  " \
"   - output interface =  " \
"   - usb audio class  =  " \
"   - digital formats  =  " \
"   - character device =  " \
"   - hw_params file   =  " \
"   - stream file      =  ")
	 	    
	    ## display the results
	    cat <<EOF

${card_display_title}
${LST_PROPS[0]}${cardlabel}
${LST_PROPS[1]}${devlabel}
${LST_PROPS[2]}${uacclass}
${LST_PROPS[3]}${formats}
${LST_PROPS[4]}${chardev}
${LST_PROPS[5]}${hwparamsfile}
${LST_PROPS[6]}${streamfile}

EOF
	fi

    done <<< "${aplay_output}"

}


function summarize() {
    ## based on the global arrays, return/echo the interfaces found

    msg=""
    nr_nonuacdo_devs=0

    if [[ ${#ALSA_UAC_DEVICES[@]} == 0 ]]; then
	## no uac device detected
	msg="${MSG_TAB}${MSG_MATCH_UACDO_NONE}"

	if [[ ${#ALSA_DO_DEVICES[@]} == 1 ]]; then
	    ## single non-uac digital out interface
	    msg="${msg}\n${MSG_TAB}${MSG_MATCH_NONUACDO_SINGLE}"
	else
	    ## multiple non-uac digital out interfaces; show how many (subtract uac devices)
	    let nr_nonuacdo_devs=${#ALSA_DO_DEVICES[@]}-${#ALSA_UAC_DEVICES[@]}
	    msg="${msg}\n${MSG_TAB}${MSG_MATCH_NONUACDO_MULTIPLE/Multiple/${nr_nonuacdo_devs}}"
	fi
    else
	## one or more uac devices found
	if [[ ${#ALSA_UAC_DEVICES[@]} == 1 ]]; then
	    ## single uac device found
	    msg="${MSG_TAB}${MSG_MATCH_UACDO_SINGLE}"
	else
	    ## multiple uac devices found; show how many
	    msg="${MSG_TAB}${MSG_MATCH_UACDO_MULTIPLE/Multiple/${#ALSA_UAC_DEVICES[@]}}"
	fi
    fi

    ## return the summary
    echo -e "${MSG_SUMMARY}${msg}"

}

function prompt_watch() {
    ## prompt the user to select a hardware address in order to watch
    ## its associated stream or hw_params file in /proc/asound.
    ## if $1 is empty: no UAC devices found
    ##
    ## excepts output of disaply_summary as param $1

    prompt="${MSG_WATCH_PROMPT}"
    summary=""

    case ${#ALSA_DO_DEVICES[@]} in
	"1")
	    ## single DO interface
	    summary="${MSG_WATCH_SINGLE}"
	    ;;
	*)
	    ## multiple DO interfaces
	    summary="${MSG_WATCH_MULTIPLE}"
	    ;;
    esac

    ## display the summary
    inform "${summary}"

    ## display the prompt
    if [[ ${#ALSA_UAC_DEVICES[@]} = 0 ]]; then
	## no UAC
	default_hw_address="${ALSA_DO_INDEXES[0]}"
	WATCH_DEVICE="$(read -e -p "${prompt}" \
-i "${default_hw_address}" WATCH_DEVICE && \
echo -e "${WATCH_DEVICE}")"
	${CMD_WATCH} -n 0.1 cat "${ALSA_DO_DEVICES[${WATCH_DEVICE}]}"
    else
	## UAC
	default_hw_address="${ALSA_UAC_INDEXES[0]}"
	WATCH_DEVICE="$(read -e -p "${prompt}" \
-i "${default_hw_address}" WATCH_DEVICE && \
echo -e "${WATCH_DEVICE}")"
	${CMD_WATCH} -n 0.1 cat "${ALSA_UAC_DEVICES[${WATCH_DEVICE}]}"

    fi

}


function alsa_device_busy() {
    ## looks for and returns processes that have exclusive access to
    ## chardev $1

    alsa_chardev="$1"

    ## try lsof while hiding/redirecting errors
    lsof_out="$(lsof -F c ${alsa_chardev} 2>/dev/null)"
    if [[ "$?" == 0 ]]; then
	## user may inspect lsof output. lsof out consist of:
	## pXXX  (XXX = numeric process id)
	## cYYY  (YYY = process name)
	## store first line by stripping out second line starting with c
	p_firstline="${lsof_out%c*}"
	## store first line/strip output of lsof by starting after first character (p) 
	## and stopping before newline character (=length of p_firstline string)
	p_id="${lsof_out:1:(${#p_firstline}-2)}"
	## get second line by filtering lsof_out from (length of p_id+1)
	p_name="${lsof_out:(${#p_firstline}+1):${#lsof_out}}"
	echo -e "in use by \`${p_name}' with pid \`${p_id}'"
    else
	## normal user can't access lsof output of system daemons
	echo -e "${MSG_RUN_AS_ROOT}"
    fi
    
}

function return_alsa_formats() {
    ## fetches and returns a comma seperated string of playback formats
    ## by feeding it dummy input while keeping the test silent 
    ## by redirecting output to /dev/null.
    ## 
    ## needs address of alsa output device in `hw:x,y' format 
    ## as single argument ($1)

    [[ ! -z "${DEBUG}" ]] && debug "entering \`${FUNCNAME}' with arguments \`$@'"

    alsa_hw_device="$1"
    ALSA_BEFORE_FORMATS="Available formats:"

    aplay_out="$(cat /dev/urandom | \
LANG=C ${CMD_APLAY} -D ${alsa_hw_device} 2>&1 >/dev/null | grep '^- ')"

    while read -r line; do format="${format}, ${line/- /}"; done <<< "${aplay_out}"
    formats="${format#, }"
    [[ ! -z "${formats}" ]] && \
	echo -e "${formats}" || \
	echo -e "${MSG_DEVICE_BUSY}"

}

function return_alsa_chardev() {
    ## constructs, tests and returns the path to node in /dev.
    ## 
    ## needs cardnr ($1) and devnr ($2) as arguments

    [[ ! -z "${DEBUG}" ]] && debug "entering \`${FUNCNAME}' with arguments \`$@'"

    cardnr="$1"
    devnr="$2"
    chardev="/dev/snd/pcmC${cardnr}D${devnr}p"

    ## test if its a character device or exit with error
    [[ -c "${chardev}" ]] && \
	echo -e "${chardev}" || \
	die "${MSG_NO_DEVICE}: \`${chardev}'"
    

}

function return_alsa_hwparamsfile() {
    ## constructs, tests and returns the path to the hw_params file in
    ## /proc
    ##
    ## needs cardnr ($1) and devnr ($2) as arguments

    [[ ! -z "${DEBUG}" ]] && debug "entering \`${FUNCNAME}' with arguments \`$@'"

    cardnr="$1"
    devnr="$2"
    hwparamsfile="/proc/asound/card${cardnr}/pcm${devnr}p/sub0/hw_params"

    ## test if its a file or exit with error
    [[ -f "${hwparamsfile}" ]] && \
	echo -e "${hwparamsfile}" || \
	die "${MSG_NO_FILE}: \`${hwparamsfile}'"

}


function return_alsa_streamfile() {
    ## constructs, tests and returns the path to the stream file in
    ## /proc to fill the ALSA_UAC_DEVICES array.
    ## 
    ## needs cardnr ($1) and devnr ($2) as arguments

    [[ ! -z "${DEBUG}" ]] && debug "entering \`${FUNCNAME}' with arguments \`$@'"

    cardnr="$1"
    devnr="$2"
    streamfile="/proc/asound/card${cardnr}/stream${devnr}"

    ## test if streamfile exist and is accessable and return it or return fixed string
    [[ -f "${streamfile}" ]] && \
	echo -e "${streamfile}" || \
	echo -e "${PROP_NOT_APPLICABLE}"

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


### main

## check if needed commands are available
CMD_APLAY=$(which aplay || command_not_found "aplay" "alsa-utils")
CMD_WATCH=$(which watch || command_not_found "watch" "procps")

## temporary stop and disable pulseaudio if its running
pulse_disable

## fetch list with alsa cards and outputs
fetch_alsadevices_list

## display a summary
summary="$(summarize)"
inform "${summary}"

## prompt to watch the monitoring file
prompt_watch

## restore pulse to state before running the script
pulse_restoreconf

### done
