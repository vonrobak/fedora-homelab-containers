#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=46'

JQA "${1}" 'del(.interfaces[]?.ethernet.flowControl)'

exit 0
