#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=29'

# delete suspend service configuration (disable it) if redirect url is null

JQA "${1}" 'del(.services.suspend | select(.redirectURL == null))'

exit 0
