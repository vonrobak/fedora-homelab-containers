#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/snmpAgent"=1'
# delete service
JQA "${1}" 'del(.services.snmpAgent.user)'
JQA "${1}" 'del(.services.snmpAgent.authProtocol)'
JQA "${1}" 'del(.services.snmpAgent.authPassPhrase)'
JQA "${1}" 'del(.services.snmpAgent.privacyProtocol)'
JQA "${1}" 'del(.services.snmpAgent.privacyPassPhrase)'

exit 0
