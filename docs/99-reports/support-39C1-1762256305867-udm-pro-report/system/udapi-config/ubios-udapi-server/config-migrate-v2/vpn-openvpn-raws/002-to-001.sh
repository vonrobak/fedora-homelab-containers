#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/openvpn/raws"=1'

JQA "${1}" 'del (.services.wanFailover.wanInterfaces[]? | select(.interface|test("^tunovpnc")))'

exit 0
