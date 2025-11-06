#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=6'
# give each dhcp server an ipVersion field, based on the address
# versions they are using:
JQA "${1}" '.services.dhcpServers[] |= . + if has("relay") then {"ipVersion": .relay.ipPair[0].localIp.version} else {"ipVersion": .rangeStart.version} end'
