#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

JQA "${1}" '
    def migrateIdsIps(config):
        config.services.idsIps.alienLoggingEnabled |= false
        | config.services.idsIps.torLoggingEnabled |= false
        | config.services.idsIps.threatLoggingEnabled |= false
        ;

    .versionDetail."services/idsIps"=5
    |
    if .services | has("idsIps") then . = migrateIdsIps(.) else . end
'

exit 0
