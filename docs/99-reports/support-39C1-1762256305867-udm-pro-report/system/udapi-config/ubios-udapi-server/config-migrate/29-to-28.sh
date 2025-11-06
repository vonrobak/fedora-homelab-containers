#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=28'

# 0. common functions

DEF_FUNCS='

  def convert_laiface_to_line:
    .id as $tmp | del(.) | .=$tmp;

  def convert_lastatic_to_line:
    .address as $tmp | del(.) | .=$tmp;

  def convert_laother_to_line:
    del(.) | .="0.0.0.0";

  def convert_la_to_line:
    if (.source == "interface") then convert_laiface_to_line
    elif (.source == "static") then convert_lastatic_to_line
    else convert_laother_to_line end;

  def convert_laiface_to_iface:
    .id as $tmp | del(.) | .id=$tmp;

  def convert_laother_to_iface:
    del(.) | .id="eth0";

  def convert_la_to_iface:
    if (.source == "interface") then convert_laiface_to_iface
    else convert_laother_to_iface end;
'

# 1. In L2TP Server Service: convert .localAddress to .wanInterface

JQA "${1}" "${DEF_FUNCS}"'
  (.services | select(has("l2tpServer"))
    | .l2tpServer | select(has("localAddress")))
      |= (.wanInterface=.localAddress | del(.localAddress)
        | .wanInterface
          |= convert_la_to_iface)
'

# 2. In IPSec s2s VPN: convert .localAddress to .localInterface

JQA "${1}" "${DEF_FUNCS}"'
  (."vpn/ipsec/site-to-site"[]? | select(has("localAddress")))
    |= (.localInterface=.localAddress | del(.localAddress)
      | .localInterface
        |= convert_la_to_line)
'

# 3. In OpenVPN: convert .tunnel.localPeer.localAddress to .tunnel.localPeer.interface

JQA "${1}" "${DEF_FUNCS}"'
  (."vpn/openvpn/peers"[]? | select(has("tunnel"))
    | .tunnel | select(has("localPeer"))
      | .localPeer | select(has("localAddress")))
        |= (.interface=.localAddress | del(.localAddress)
           | .interface
             |= convert_la_to_line)
'

exit 0
