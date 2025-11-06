#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=44'

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
    local key="<FILTERED>{1}"
    local ubnthal_system_file="/proc/ubnthal/system.info"

    [ -f "${ubnthal_system_file}" ] && {
        get_named_value "${key}" "<FILTERED>{ubnthal_system_file}"
    }
}

# @brief Get a path to board config file
#
# @param 1 - board id
get_board_config_path()
{
    local board_id="${1}"
    local match="/usr/share/ubios-udapi-server/config-board/*-${board_id}.json"

    # match should already be equal to our file, but we need to be sure
    ls ${match} | head -1
}

# @brief Get a json array of interfaces that use the given media according to board config file.
#
# @param 1 - path to board config file
# @param 2 - media to match with
# @return error code denoting if there was a parsing/processing error.
#         stdout will contain a json array with interface names (as strings).
#         Note that if input file is empty, the return code will be 0, but stdout will be empty.
#         Same empty stdout will be the case when error has occured.
get_interfaces_by_media()
{
    local board_config_path="${1}"
    local media="${2}"

    # error code, monochrome, compact
    jq -eMc --arg media "${media}" '[ .interfaces[] | .identification | select(.media==$media) | .id ]' "${board_config_path}"
}

# First, look for the board-config in the same folder as our input config.
# It should have the same name as input config with "board-" prefix and without .45_to_44 suffix.
# This is meant to be a way to test this functionality without ubnthal or board-config file in known location.
# When there is no file matching the conditions, it is assumed we are running on a console.
BOARD_CONFIG_PATH="$(dirname "$1")/board-$(basename "$1" ".45_to_44")"
[ -f "$BOARD_CONFIG_PATH" ] || {
    BOARD_ID=$(get_ubnthal_system "systemid")
    [ -z "$BOARD_ID" ] && exit 0

    BOARD_CONFIG_PATH=$(get_board_config_path "${BOARD_ID}")
    [ -z "$BOARD_CONFIG_PATH" ] && exit 0
}

GE_INTERFACES="$(get_interfaces_by_media "${BOARD_CONFIG_PATH}" "GE")"
[ $? -ne 0 -o -z "$GE_INTERFACES" ] && {
    echo "Invalid contents of board config file" >&2
    exit 0
}

# When interfaces with GE media have their speed set to 2500-full - it should be replaced with auto
QUERY='( .interfaces[]? | select(.identification.id==$interfaces[]) | .status.speed | select(.=="2500-full")) |= "auto"'
JQA "${1}" "$QUERY" "--argjson interfaces "${GE_INTERFACES}""
