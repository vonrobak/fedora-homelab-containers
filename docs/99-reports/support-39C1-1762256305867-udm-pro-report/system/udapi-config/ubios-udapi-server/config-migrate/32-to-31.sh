#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=31'

# no need to change null to factory-default UUID

exit 0
