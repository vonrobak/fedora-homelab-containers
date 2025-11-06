#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=25'

# N/A - removed routes with invalid destination cannot be restored

exit 0
