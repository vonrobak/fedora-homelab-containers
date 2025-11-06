#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=38'

# Proxy BLE gateway to UDAPI. Migration was done only for UXG-PRO devices

# @brief Get named value delimited by '=' from the given file
#
# @param 1 - item name
# @param 2 - file to get the value from
get_named_value()
{
    sed -n "s/^${1}=//p" "${2}"
}

# @brief Get named value from ubnthal system.info
#
# @param 1 - item name
get_ubnthal_system()
{
    local ubnthal_system_file="/proc/ubnthal/system.info"

    if [ -f "${ubnthal_system_file}" ]; then
        get_named_value "${1}" "${ubnthal_system_file}"
    fi
}

BOARD_ID="$(get_ubnthal_system "systemid")"
if [ "${BOARD_ID}" = "ea19" ]; then
    JQA "${1}" '.services.bleHTTPTransport.httpHostAddress = "http://127.0.0.1:1080"'
fi
exit 0
