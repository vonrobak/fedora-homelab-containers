#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=10'

# pppoe mtu can be higher than its parent
# extend MSS clamping to any interface, move it from pppoe
JQA "${1}" '
    def pppoe_parent_id($ifc):
        $ifc.pppoe.interface.id;
    def ppp_mtu($ifc):
        $ifc.status.mtu // 1492;
    def parent_mtu($ifcs; $parent_id):
        $ifcs[]? | select(.identification.id == $parent_id) | .status.mtu // 1500;
    def parent_enabled($ifcs; $parent_id):
        $ifcs[]? | select(.identification.id == $parent_id) | .status.enabled // false;
    .interfaces as $ifcs |
    ( .interfaces[]? | select(has("pppoe")) )
        |=
    (
        pppoe_parent_id(.) as $parent_id |
        parent_mtu($ifcs; $parent_id) as $parent_mtu |
        parent_enabled($ifcs; $parent_id) as $parent_enabled |
        ppp_mtu(.) as $mtu |
        if $mtu > $parent_mtu then
            .status.mtu = $parent_mtu
        else
            .status.mtu = $mtu
        end |
        if .status.enabled and ($parent_enabled | not) then
            .status.enabled = false
        else
            .
        end |
        if (.pppoe.mssClamping == true) then
            if (.status.mtu - 40 < .pppoe.mssClampSize) then
                .ipv4.mssClamping.mssClampSize=.status.mtu - 40
            else
                .ipv4.mssClamping.mssClampSize=.pppoe.mssClampSize
            end |
            if (.ipv4.mssClamping.mssClampSize >= 1240) then
                .ipv6.mss6Clamping.mssClampSize=.ipv4.mssClamping.mssClampSize - 20
            else
                .ipv6.mss6Clamping.mssClampSize=1220
            end
        else
            .
        end |
        del(.pppoe.mssClampSize) |
        del(.pppoe.mssClamping)
    )
'

exit 0
