#!/bin/sh

. "$(dirname "${0}")"/../JQ
. "$(dirname "${0}")"/../BOARD
JQA "${1}" '.versionDetail."services/sshServer"=2'

# ux: a667
# uxmax: a69b
is_ux_device()
{
    local sys_id="$(get_ubnthal_system "systemid")"
    if [ "${sys_id}" = "a667" -o "${sys_id}" = "a69b" ]; then
        echo "y"
    else
        echo "n"
    fi
}

if [ "$(is_ux_device)" = "y" ]; then
    JQA "${1}" 'del(.services.sshServer)'
fi
