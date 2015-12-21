#!/usr/bin/env bash

counter=0
grep_re="^([0-9]+):(APLAY|ARECORD)"
for char in {a..z}; do
    while read bzfile; do
	startnr=0
	endnr=0
	lines=0
	aplay=""
	jaap="$(bunzip2 -c ${bzfile})"
	echo "##### file: \`${bzfile}'" 1>&2;
	startline="$(echo "${jaap}" | grep -nE ^APLAY)"
	[[ "${startline}" =~ ${grep_re} ]] && startnr=${BASH_REMATCH[1]}
	endline="$(echo "${jaap}" | grep -nE ^ARECORD)"
	[[ "${endline}" =~ ${grep_re} ]] && endnr=${BASH_REMATCH[1]}
	lines=$(( ${endnr} - ${startnr} - 1 ))
	
	#echo "nr lines: ${lines}"
	aplay_raw="$(echo "${jaap}" | grep -A${lines} -E ^APLAY | tail -n+2)"
	#aplay="$(tail -n+1 "${aplay_raw}")"
	#aplay="${aplay_raw//^APLAY'\n'/#### start}"
	#echo "*** aplay output ${char}"
	printf "%s" "${aplay_raw}" > /tmp/${bzfile##*/}.raw
	#printf "\n## end\n" 
	#break
    done< <(ls -1 ${char}*/*/*.bz2)
done
