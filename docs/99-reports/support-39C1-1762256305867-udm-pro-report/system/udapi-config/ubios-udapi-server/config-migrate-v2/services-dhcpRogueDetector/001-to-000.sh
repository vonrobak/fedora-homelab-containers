#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" 'del(.services.dhcpRogueDetector)'
JQA "${1}" 'del(.versionDetail."services/dhcpRogueDetector") |
            del(.services.dhcpRogueDetector)'

exit 0
