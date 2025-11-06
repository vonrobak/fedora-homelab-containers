#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=16'

# 1. If 'dhcp6PDRequestEnabled' set to 'true' and 'dhcp6PDRequestSize' not set then set it to 'null';
JQA "${1}" '(.interfaces[]?.ipv6? | select((.dhcp6PDRequestEnabled==true) and (has("dhcp6PDRequestSize") | not))) |= (.dhcp6PDRequestSize=null)'

# 2. Remove 'dhcp6PDRequestEnabled'.
JQA "${1}" '(.interfaces[]?.ipv6? | select(has("dhcp6PDRequestEnabled"))) |= del(.dhcp6PDRequestEnabled)'

# 3. Remove 'ndpProxyUseFromInterface'.
JQA "${1}" '(.interfaces[]?.ipv6? | select(has("ndpProxyUseFromInterface"))) |= del(.ndpProxyUseFromInterface)'

exit 0
