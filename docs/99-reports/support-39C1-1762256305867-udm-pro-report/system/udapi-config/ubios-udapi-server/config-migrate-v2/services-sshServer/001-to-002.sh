#!/bin/sh
. "$(dirname "${0}")"/../JQ
. "$(dirname "${0}")"/../BOARD

JQA "${1}" '.versionDetail."services/sshServer"=2'

is_default()
{
    JQT "${1}" '.services.unifiNetwork.enabled' && echo "n" || echo "y"
}

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

is_ssh_srv_enabled()
{
    JQT "${1}" '.services.sshServer.enabled' && echo "y" || echo "n"
}

if [ "$(is_default "${1}")" = "y" -a "$(is_uxg_device)" = "y" -a "$(is_ssh_srv_enabled "${1}")" = "n" ]; then
   JQA "${1}" '.services += { "sshServer": { "enabled": true, "sshPort": 22 } }'
fi
