#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/geoipFiltering"=2'
JQA "${1}" 'if .services | has("geoipFiltering") then .services.geoipFiltering.enableLogging = false else . end'
exit 0
