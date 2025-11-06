#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=17'

# 1. If 'dhcp6PDRequestSize' set then set 'dhcp6PDRequestEnabled' to 'true'.
JQA "${1}" '(.interfaces[]?.ipv6? | select(has("dhcp6PDRequestSize"))) |= (.dhcp6PDRequestEnabled=true)'

# 2. If 'dhcp6PDRequestSize' set to 'null' then remove 'dhcp6PDRequestSize'.
JQA "${1}" '(.interfaces[]? | select(has("ipv6") and .ipv6.dhcp6PDRequestSize==null)) |= del(.ipv6.dhcp6PDRequestSize)'

exit 0
