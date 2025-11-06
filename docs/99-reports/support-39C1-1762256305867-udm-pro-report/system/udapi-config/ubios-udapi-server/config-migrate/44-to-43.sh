#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=43'

# Remove geoip related rules from /firewall/{filter,mangle}.
JQA "${1}" 'del(."firewall/filter"[]?."rules"[]?|select(has("geoip")))'
JQA "${1}" 'del(."firewall/mangle"[]?."rules"[]?|select(has("geoip")))'

exit 0
