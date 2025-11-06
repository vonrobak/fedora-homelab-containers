#!/bin/sh
. "$(dirname "${0}")"/../JQ
. "$(dirname "${0}")"/../BOARD

JQA "${1}" '.versionDetail."services/sshServer"=3'

is_default()
{
    file_name="/data/udapi-config/mgmt"

    if [ ! -f "$file_name" ]; then
        echo "$file_name doesn't exist."
    else
        if [ "$(cat "$file_name" | grep 'mgmt.is_setup_completed' | cut -d '=' -f 2)" = "false" ]; then
            echo "y"
        else
            echo "n"
        fi
    fi
}

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

is_ssh_srv_enabled()
{
    JQT "${1}" '.services.sshServer.enabled' && echo "y" || echo "n"
}

if [ "$(is_default "${1}")" = "y" -a "$(is_ux_device)" = "y" -a "$(is_ssh_srv_enabled "${1}")" = "n" ]; then
   JQA "${1}" '.services += { "sshServer": { "enabled": true, "sshPort": 22 } }'
fi
