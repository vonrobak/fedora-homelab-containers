#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=41'

# enable bleHTTPTransport service for UXGPRO in v41

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
    if [ -e "/config/unifi" ]; then
        SERVICE_UUID="3d8bac06-22b2-4cf0-a974-bb256b4810f5"
    else
        SERVICE_UUID="ae1655d6-86ec-4d42-a92d-42cf6a219e76"
    fi

    JQA "${1}" '.services + {
        bleHTTPTransport: {
            enabled: true,
            serviceUUID: $uuid,
            advertiseName: null,
            advertiseMAC: null,
            advertiseIPv4: null,
            httpHostAddress: "https://127.0.0.1:443"
        }
    }' "--arg uuid ${SERVICE_UUID}"
fi


exit 0
