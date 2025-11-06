#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=24'

# N/A - deleted IDs cannot be restored

exit 0
