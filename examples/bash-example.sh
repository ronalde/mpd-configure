#!/usr/bin/env bash
## sample script for advanced usage of alsa-capabilities.
## this script returns the monitor file for hw:0,0

## store the monitorfile 
declare -a ALSA_AIF_MONITORFILES=()

source alsa-capabilities

return_alsa_interface -a "hw:0,0" -q

printf "%s\n" "${ALSA_AIF_MONITORFILES[@]}"
