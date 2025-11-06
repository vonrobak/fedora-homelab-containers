#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=17'

# Remove system/timezone field.
JQA "${1}" 'del(.system.timezone)'

exit 0
