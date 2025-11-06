#!/bin/sh

. "$(dirname "${0}")"/../JQ
. "$(dirname "${0}")"/../BOARD
JQA "${1}" '.versionDetail."services/sshServer"=1'

# uxglite: a677
# uxgmax: a690
# uxgent: ea3e
# uxgpro: ea19
is_uxg_device()
{
    local sys_id="$(get_ubnthal_system "systemid")"
    if [ "${sys_id}" = "a677" -o "${sys_id}" = "a690" -o "${sys_id}" = "ea3e" -o "${sys_id}" = "ea19" ]; then
        echo "y"
    else
        echo "n"
    fi
}

if [ "$(is_uxg_device)" = "y" ]; then
    JQA "${1}" 'del(.services.sshServer)'
fi
