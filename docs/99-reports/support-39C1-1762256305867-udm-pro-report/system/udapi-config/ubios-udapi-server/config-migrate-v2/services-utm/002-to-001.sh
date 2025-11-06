#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/utm"=1'

# no need to downgrade from 002 to 001 in cases if no utm service
JQT "${1}" '.services.utm' || exit 0

# remove ADs filtering
JQA "${1}" 'del(.services.utm.dnsFilter[].adsFilter)'

exit 0
