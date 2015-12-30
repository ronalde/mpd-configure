formats=(S8 U8 S16_LE S16_BE U16_LE U16_BE S24_LE S24_BE U24_LE U24_BE S32_LE S32_BE U32_LE U32_BE FLOAT_LE FLOAT_BE FLOAT64_LE FLOAT64_BE IEC958_SUBFRAME_LE IEC958_SUBFRAME_BE MU_LAW A_LAW IMA_ADPCM MPEG GSM SPECIAL S24_3LE S24_3BE U24_3LE U24_3BE S20_3LE S20_3BE U20_3LE U20_3BE S18_3LE S18_3BE U18_3LE U18_3BE)

CMD_APLAY="$(which aplay)"
source alsa-capabilities
formats=("$(return_alsa_formats "${1:-hw:0,0}")")

#printf "formats: %s\n" "$(printf "%s" "${formats[@]}")" 2>&1;

rates=()
baserates=(44100 48000)
for baserate in ${baserates[@]}; do
    for i in 4 2 1; do
	rates+=($(( baserate * $i )))
    done 

done
#printf "rates: %s\n" "$(printf "%s " "${rates[@]}")" 2>&1;


hw=""


alsa_hw_device="${1:-hw:0,0}"
printf "using device: %s\n" "${alsa_hw_device}" 2>&1;
aplay_opts_pre=()
aplay_opts_pre+=(-D "${alsa_hw_device}")
aplay_opts_pre+=(-f "MPEG")
aplay_opts_pre+=(-c "2")
aplay_opts_post=()
format=""
pseudo_random="30985218341569576428057261168568123489906994"

rate_notaccurate_re=".*Warning:.*not[[:space:]]accurate[[:space:]]\(requested[[:space:]]=[[:space:]]([0-9]+)Hz,[[:space:]]got[[:space:]]=[[:space:]]([0-9]+)Hz\).*"
badspeed_re=".*bad[[:space:]]speed[[:space:]]value.*"
sampleformat_nonavailable_re=".*Sample[[:space:]]format[[:space:]]non[[:space:]]available.*"
wrongformat_re=".*wrong[[:space:]]extended[[:space:]]format.*"
default_re=".*Playing[[:space:]]raw[[:space:]]data.*"


function get_rates() {

    noerror=
    format="$1"
    for rate in ${rates[@]}; do
	unset aplay_opts_post
	aplay_opts_post=(-f "${format}")
	aplay_opts_post+=(-r "${rate}")
	aplay_out="$(echo "${pseudo_random}" | \
LANG=C ${CMD_APLAY} "${aplay_opts_pre[@]}" "${aplay_opts_post[@]}" 2>&1 >/dev/null)"
	
	if [[ $? -eq 0 ]]; then
	    linescount="$(printf "%s\n" "${aplay_out[@]}" | wc -l)"
	    #printf "rate %s aplaylines: %s\n" "${rate}" "${linescount}" 1>&2;
	    while read -r line; do
		if [[ "${line}" =~ ${default_re} ]] && [[ ${linescount} -eq 1 ]]; then
		    printf "%s\n" "${rate}"			    
		fi
	    done<<<"${aplay_out}"
	fi
    done

}

#get_formats
for format in ${formats[@]}; do
    str_format="${format//,/}"
    printf "%s %-18s: " "-" "${str_format}" 2>&1;
    declare -a rates_supported
    rates_supported+=("$(get_rates "${str_format}")")
    IFS=$'\n' sorted_rates=($(sort -u -n <<<"${rates_supported[*]}"))
    printf "%s " "${sorted_rates[@]}"
    printf "\n"
    #printf "%s\n" "${rates_supported["${str_format}"]}"
done 

