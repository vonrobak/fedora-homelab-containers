#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=15'

# delete persisted RADIUS server certificates so they'll be re-generated
# this script will be run as part of unittests, let's check that /config
# is a symlink to /mnt/data/udapi-config -> we are (most likely) on the device
config_dir="/config"
real_config_dir="/mnt/data/udapi-config"
if [ -L "${config_dir}" ]; then
    target=$(readlink -n "${config_dir}")
    if [ "${target}" == "${real_config_dir}" ]; then
        rm -rf "${config_dir}/raddb/certs"
    fi
fi

exit 0
