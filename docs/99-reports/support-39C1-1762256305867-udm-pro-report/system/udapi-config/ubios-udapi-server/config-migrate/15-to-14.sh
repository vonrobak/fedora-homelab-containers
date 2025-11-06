#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=14'

# N/A - deleted IDs cannot be restored

exit 0
