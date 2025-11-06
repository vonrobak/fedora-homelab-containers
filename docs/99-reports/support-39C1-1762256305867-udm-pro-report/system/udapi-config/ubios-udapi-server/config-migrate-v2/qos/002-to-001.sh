#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."qos"=1'

# remove qos fw queue priority
JQA "${1}" 'del(."qos".fw.queues[]?.priority)'

exit 0
