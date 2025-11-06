#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."routes/ospf/areas"=2'
JQA "${1}" 'del(."routes/ospf/areas"[]?.exportAccessList)'
JQA "${1}" 'del(."routes/ospf/areas"[]?.importAccessList)'

exit 0
