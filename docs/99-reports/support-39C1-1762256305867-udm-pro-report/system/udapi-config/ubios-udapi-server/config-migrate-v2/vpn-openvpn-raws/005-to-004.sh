#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/openvpn/raws"=4'

# Change interface source to WAN source
JQA "${1}" '
  def convert_to_wan_no_version(selector):
      {"source": "wan"};
  def convert_to_wan(selector):
      {"source": "wan", "ipVersion": selector.ipVersion};

  (."vpn/openvpn/raws"[]? | select(has("localAddress")) | select(.localAddress.source == "interface") | select(.localAddress.ipVersion != null) | .localAddress) |= convert_to_wan(.)
  | (."vpn/openvpn/raws"[]? | select(has("localAddress")) | select(.localAddress.source == "interface") | select(.localAddress.ipVersion == null) | .localAddress) |= convert_to_wan_no_version(.)
'

exit 0
