#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=2'
JQA "${1}" 'if (.services.geoipFiltering.countryList | length) == 0 then del(.services.geoipFiltering) else . end'
JQT "${1}" '.services.geoipFiltering?' \
    && JQA "${1}" '.services.geoipFiltering |= if .interfaces == null then .interfaces=null else . end' \
    && JQA "${1}" '.services.geoipFiltering |= if (.interfaces | length) == 0 and .interfaces != null then .interfaces=null | .enabled=false else . end' \
    && JQA "${1}" '.services.geoipFiltering.enabled |= if type == "boolean" then . else false end' \
    && JQA "${1}" '.services.geoipFiltering.action |= if type == "string" then . else "block" end' \
    && JQA "${1}" '.services.geoipFiltering.direction |= if type == "string" then . else "both" end'
exit 0 #success
