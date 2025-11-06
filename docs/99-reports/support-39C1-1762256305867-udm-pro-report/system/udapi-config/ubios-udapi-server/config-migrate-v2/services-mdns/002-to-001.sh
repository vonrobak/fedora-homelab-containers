#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/mdns"=1
        | del(.services?.mdns?.reflectIPVersion)
        | del(.services?.mdns?.reflectMirror)
        | del(.services?.mdns?.reflectFilter)'

exit 0
