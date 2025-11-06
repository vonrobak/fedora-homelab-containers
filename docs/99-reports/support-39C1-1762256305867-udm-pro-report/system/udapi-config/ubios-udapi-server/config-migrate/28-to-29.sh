#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=29'

# 0. common functions

DEF_FUNCS='
  def sw(str):
    .|startswith(str);

  def is_ip:
    .|sw("0") or sw("1") or sw("2") or sw("3") or sw("4") or
      sw("5") or sw("6") or sw("7") or sw("8") or sw("9");

  def convert_line_to_la_ip:
    . as $tmp | del(.) | .source="static" | .address=$tmp;

  def convert_line_to_la_iface:
    . as $tmp | del(.) | .source="interface" | .id=$tmp;

  def convert_line_to_la:
    if (.|is_ip) then convert_line_to_la_ip
    else convert_line_to_la_iface end;

  def convert_iface_to_la:
    .id as $tmp | del(.) | .source="interface" | .id=$tmp;
'

# 1. In L2TP Server Service: convert .wanInterface to .localAddress

JQA "${1}" "${DEF_FUNCS}"'
  (.services | select(has("l2tpServer"))
    | .l2tpServer | select(has("wanInterface")))
      |= (.localAddress=.wanInterface | del(.wanInterface)
        | .localAddress
          |= convert_iface_to_la)
'

# 2. In IPSec s2s VPN: convert .localInterface to .localAddress

JQA "${1}" "${DEF_FUNCS}"'
  (."vpn/ipsec/site-to-site"[]? | select(has("localInterface")))
    |= (.localAddress=.localInterface | del(.localInterface)
      | .localAddress
        |= convert_line_to_la)
'

# 3. In OpenVPN: convert .tunnel.localPeer.interface to .tunnel.localPeer.localAddress

JQA "${1}" "${DEF_FUNCS}"'
  (."vpn/openvpn/peers"[]? | select(has("tunnel"))
    | .tunnel | select(has("localPeer"))
      | .localPeer | select(has("interface")))
        |= (.localAddress=.interface | del(.interface)
           | .localAddress
             |= convert_line_to_la)
'

exit 0
