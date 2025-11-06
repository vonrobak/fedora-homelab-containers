#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
# Remove "proxied" field
JQA "${1}" '.versionDetail."services/ddns"=2 |
            del(.services?.ddns?.clients[]? | .proxied)'

exit 0
