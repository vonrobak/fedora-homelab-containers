#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=5'
# remove the ipVersion field from each dhcp server:
JQA "${1}" 'del(.services.dhcpServers[].ipVersion)'
