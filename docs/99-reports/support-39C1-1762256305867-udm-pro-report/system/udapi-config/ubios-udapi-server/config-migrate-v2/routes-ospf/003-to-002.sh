#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."routes/ospf"=2'
JQA "${1}" 'del(."routes/ospf".redistributeStatic.accessList)'
JQA "${1}" 'del(."routes/ospf".redistributeConnected.accessList)'

exit 0
