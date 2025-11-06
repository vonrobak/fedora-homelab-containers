#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=35'

# N/A - interface has only allowed speed

exit 0

