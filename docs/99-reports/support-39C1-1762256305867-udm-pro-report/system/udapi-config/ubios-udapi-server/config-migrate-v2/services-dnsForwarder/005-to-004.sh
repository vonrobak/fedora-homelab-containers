#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/dnsForwarder"=4'

# remove new custom DNS entries
JQA "${1}" 'del(.services?.dnsForwarder? | .nxdomainRecords, .ptrRecords)'

exit 0
