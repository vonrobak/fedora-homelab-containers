#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
. "$(dirname "${0}")"/../BOARD # include board config helper script

CONFIG_PATH="${1}"
JQA "${CONFIG_PATH}" '.versionDetail."bridge-firewall"=2'

MODEL=$(get_board_model "${CONFIG_PATH}") || {
    exit ${?}
}

[ "${MODEL}" = "udm-ent" -o "${MODEL}" = "uxg-ent" ] && {
    JQA "${CONFIG_PATH}" 'del(."bridge-firewall/broute"[])'
}

exit 0
