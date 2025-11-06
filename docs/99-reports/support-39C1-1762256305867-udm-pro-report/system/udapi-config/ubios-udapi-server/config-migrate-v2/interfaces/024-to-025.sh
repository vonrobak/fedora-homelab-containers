#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# Bump up version.
# Force all known radio VLAN bridge members to become dynamic.
JQA "${1}" '
    def is_bridge($ifc):
        ($ifc | select(.identification.type == "bridge" and has("bridge"))) // false;

    def is_radio($id):
        [ "ra", "apcli", "ath", "vwire" ] as $radio_iface_patterns |
        [ $radio_iface_patterns[] | . as $pattern | select($id | startswith($pattern)) ] | length == 1;

    def could_be_vlan($id):
        ($id | contains(".")) // false;

    def is_radio_vlan($id):
        (is_radio($id) and could_be_vlan($id)) // false;

    .versionDetail.interfaces=25
    |
    (.interfaces[]? | select(is_bridge(.)).bridge.interfaces[]? | select(is_radio_vlan(.id))) |= ( .dynamic = true )
'

exit 0
