#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=39'

# remove monitors IDs
JQA "${1}" 'del(.services.wanFailover.wanInterfaces[]?.monitors[]?.id)'

exit 0
