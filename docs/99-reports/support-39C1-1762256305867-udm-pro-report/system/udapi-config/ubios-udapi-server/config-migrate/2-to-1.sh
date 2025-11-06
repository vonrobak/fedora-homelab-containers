#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=1'
JQT "${1}" '.services.geoipFiltering?' \
    && JQA "${1}" '.services.geoipFiltering.allowPrivateAddressSpace |= if type == "boolean" then . else true end' \
    && JQA "${1}" '.services.geoipFiltering.allowSharedAddressSpace |= if type == "boolean" then . else true end' \
    && JQA "${1}" '.services.geoipFiltering.allowOwnAddressSpace |= if type == "boolean" then . else true end'
exit 0 #success
