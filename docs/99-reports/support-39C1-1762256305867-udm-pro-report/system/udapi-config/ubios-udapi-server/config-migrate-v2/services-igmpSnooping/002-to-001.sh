#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
. "$(dirname "${0}")"/../BOARD # include board config helper script

CONFIG_PATH="${1}"
JQA "${CONFIG_PATH}" '.versionDetail."services/igmpSnooping"=1'

MODEL=$(get_board_model "${CONFIG_PATH}") || {
    exit ${?}
}

[ "${MODEL}" = "udr" ] && {
    JQA "${CONFIG_PATH}" 'del(.services.igmpSnooping)'
}

exit 0
