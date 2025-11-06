#!/bin/sh
. "$(dirname "${0}")"/../JQ
. "$(dirname "${0}")"/../BOARD
JQA "${1}" '.versionDetail."interfaces"=20'


BOARD_CONFIG_PATH=$(get_board_config_path "${1}") || {
    exit ${?}
}

is_sfp28_interface()
{
    local sfp28_if="$(jq -r --arg iface "${1}" '.interfaces[]|select(.["identification"]["id"]==$iface)' ${BOARD_CONFIG_PATH})"
    local sfp28_if_media="$(echo ${sfp28_if} | jq -r '.["identification"]["media"]')"
    [ "${sfp28_if_media}" = "SFP28" ] && echo "y" || echo "n"
}

get_sfp_interface_id()
{
    echo "$(jq -r --arg media "${1}" '.interfaces[]|select(.["identification"]["media"] | tostring | startswith($media)).identification.id' ${BOARD_CONFIG_PATH})"
}

get_sfp_interface_speed()
{
    echo "$(jq -r --arg id "${2}" '.interfaces[]|select(.["identification"]["id"] == $id).status.speed' ${1})"
}

append_sfp_fec()
{
    JQA "${1}" '.interfaces[] |= if .identification.id == $id then .ethernet += { "sfp": { "fec": $fec } } else . end' "--arg id ${2} --arg fec ${3}"
}

for id in $(get_sfp_interface_id "SFP"); do
    if [ "$(is_sfp28_interface "${id}")" = "y" -a "$(get_sfp_interface_speed "${1}" "${id}")" = "auto" ]; then
        append_sfp_fec "${1}" "${id}" "auto"
    elif [ "$(is_sfp28_interface "${id}")" = "y" -a "$(get_sfp_interface_speed "${1}" "${id}")" = "25000-full" ]; then
        append_sfp_fec "${1}" "${id}" "baser"
    else
        append_sfp_fec "${1}" "${id}" "none"
    fi
done
