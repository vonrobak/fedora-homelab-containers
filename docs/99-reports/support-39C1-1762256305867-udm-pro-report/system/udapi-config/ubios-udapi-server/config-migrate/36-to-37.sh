#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=37'

# Unsupported firewall rule `!tcp_udp` would be rejected.
JQA "${1}" 'del (."firewall/nat"[]? | select(.protocol == "!tcp_udp"))'
JQA "${1}" 'del (."firewall/filter"[]?.rules[]? | select(.protocol == "!tcp_udp"))'
JQA "${1}" 'del (."firewall/mangle"[]?.rules[]? | select(.protocol == "!tcp_udp"))'

exit 0
