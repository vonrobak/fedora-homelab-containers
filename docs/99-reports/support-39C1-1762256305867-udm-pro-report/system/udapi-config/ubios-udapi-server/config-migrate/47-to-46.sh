#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=46'

# delete all log and geoip attributes in the firewall/pbr rules
JQA "${1}" 'del(."firewall/pbr".rules[]?.log)'
JQA "${1}" 'del(."firewall/pbr".rules[]?.geoip)'

exit 0
