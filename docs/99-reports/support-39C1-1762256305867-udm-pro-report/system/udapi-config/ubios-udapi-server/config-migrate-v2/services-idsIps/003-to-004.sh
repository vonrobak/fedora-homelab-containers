#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

JQA "${1}" '
    def getSslInspectionConfig(config):
        if config.services.idsIps.sslInspectionEnabled? == true then config.services.idsIps.sslInspectionEnabled = true
        else config.services.idsIps.sslInspectionEnabled = false
        end
        ;

    .versionDetail."services/idsIps"=4
    |
    if .services | has("idsIps") then . = getSslInspectionConfig(.) else . end
'

exit 0
