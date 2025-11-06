#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=26'

# use ubnt-ipcalc from PATH or local one for unit tests
curr_dir="$(dirname "${0}")"
ipcalc_bin="$(which ubnt-ipcalc 2>/dev/null || echo "${curr_dir}/ubnt-ipcalc")"
if [ ! -x "${ipcalc_bin}" ]; then
    echo "ubnt-ipcalc does not exist."
    exit 1
fi

# Removes all static routes with invalid destination.
#
# - Validates all (subnets only) routes/static[].destination with `ubnt-ipcalc` script.
# - If it returns non zero error code the destination is invalid.
# - If returned network-cidr is not equal to destination, the destination is invalid.

cat "${1}" | jq '."routes/static"[]? | .destination' | tr -d '"' | grep '/' | \
    while IFS= read -r destination; do
        valid_net=$("${ipcalc_bin}" --quiet --network-cidr "${destination}")
        ret_code=$?
        if [ ${ret_code} -ne 0 ]; then
            echo "${destination}"
        else
            if [ "${valid_net}" != "${destination}" ]; then
                echo "${destination}"
            fi
        fi
    done | \
    while IFS= read -r invalid_destination; do
        JQA "${1}" 'del(."routes/static"[]? | select(.destination == "'"${invalid_destination}"'"))'
    done

exit 0
