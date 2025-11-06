#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."firewall/mangle"=4'

JQA "${1}" 'del(."firewall/mangle"[]."rules"[] | select(has("target")) | select(.target == "SSL_INSPECTION"))'

exit 0
