#!/usr/bin/env bash

## helper script which converts bzipped2 files stored in ./*/*/*.bz2
## from alsa's alsa-test.sh database to proper aplay output files
## stored in /tmp/*.bz2.raw.
## Meant for mass testing of ./alsa-capabilities.

counter=0
grep_re="^([0-9]+):(APLAY|ARECORD)"
for char in {a..z}; do
    while read bzfile; do
	startnr=0
	endnr=0
	lines=0
	aplay=""
	## unzip the source file
	bzip_source="$(bunzip2 -c ${bzfile})"
	echo "##### file: \`${bzfile}'" 1>&2;
	## get the line number where the aplay -l output starts
	startline="$(echo "${bzip_source}" | grep -nE ^APLAY)"
	[[ "${startline}" =~ ${grep_re} ]] && startnr=${BASH_REMATCH[1]}
	## get the line number where the aplay -l output ends
	endline="$(echo "${bzip_source}" | grep -nE ^ARECORD)"
	[[ "${endline}" =~ ${grep_re} ]] && endnr=${BASH_REMATCH[1]}
	## calculate the number of lines in between
	lines=$(( ${endnr} - ${startnr} - 1 ))
	## store the lines between APLAY and ARECORD in a variable
	aplay_raw="$(echo "${bzip_source}" | grep -A${lines} -E ^APLAY | tail -n+2)"
	## store it in an file, appending .raw to the source file
	printf "%s" "${aplay_raw}" > /tmp/${bzfile##*/}.raw
    done< <(ls -1 ${char}*/*/*.bz2)
done
