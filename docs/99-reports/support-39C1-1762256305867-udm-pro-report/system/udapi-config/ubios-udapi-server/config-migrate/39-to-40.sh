#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=40'

# make monitors IDs null
JQA "${1}" '.services.wanFailover.wanInterfaces[]?.monitors[]? |= . + {"id": null}'

exit 0
