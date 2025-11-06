#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts

# .services.dhcpServers[]?.name has become mandatory
JQA "${1}" '.version=20'
JQA "${1}" '
    def default_server_name(servers):
        servers | [key<FILTERED>[]? as $i | .[$i] | if (has("name") | not) then .name="default-" + ($i | tostring) else . end];

    (.services | select(has("dhcpServers")) | .dhcpServers) |= default_server_name(.)
'

exit 0