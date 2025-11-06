#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=28'

# delete REDIRECT targets; up until now REDIRECT was considered a user <FILTERED>,
# from now on it's a special target which would change the behavior of the device

JQA "${1}" 'del (."firewall/nat"[]? | select(.target == "REDIRECT"))'

exit 0
