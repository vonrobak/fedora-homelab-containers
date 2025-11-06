#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=23'

# Helpers
DEFS='
    def id_in_array($id; $arr):
        $arr | index($id) != null // false;

    def get_ifc($ifcs; $id):
        ($ifcs[]? | select(.identification.id == $id)) // null;

    def is_pppoe($ifc):
        ($ifc | select(.identification.type == "pppoe" and has("pppoe"))) // false;

    def is_vlan($ifc):
        ($ifc | select(.identification.type == "vlan" and has("vlan"))) // false;

    def is_bridge($ifc):
        ($ifc | select(.identification.type == "bridge" and has("bridge"))) // false;

    def is_lag($ifc):
        ($ifc | select(.identification.type == "lag" and has("lag"))) // false;

    def is_switch($ifc):
        ($ifc | select(.identification.type == "switch" and has("switch"))) // false;

    def pppoe_parent_id($ifc):
        $ifc.pppoe.interface.id;

    def iface_mtu($ifc):
        $ifc.status.mtu // 1500;

    def iface_enabled($ifc):
        $ifc.status.enabled // false;

    def parent_mtu($ifcs; $parent_id):
        get_ifc($ifcs; $parent_id).status.mtu // 1500;

    def parent_enabled($ifcs; $parent_id):
        get_ifc($ifcs; $parent_id).status.enabled // false;

    def has_addr($ifc):
        $ifc | select(
            (.addresses[]?.origin != "linkLocal") //
            (.ipv6?.dhcp6PDUseFromInterface) //
            (.ipv6?.ndpProxyUseFromInterface)
        ) // false;
'

# Decrease PPPoE MTU if it's greater than the parent interface MTU (counts with overhead).
# Disable PPPoE interface if the parent interface is disabled.
JQA "${1}" "$DEFS"'
    [.interfaces[]?] as $ifcs |
    8 as $ppoe_eth_overhead |

    (.interfaces[]? | select(is_pppoe(.))) |=(
        pppoe_parent_id(.) as $pppoe_parent_id |
        iface_mtu(.) as $current_mtu |
        iface_enabled(.) as $current_enabled |
        parent_mtu($ifcs; $pppoe_parent_id) as $pppoe_parent_mtu |
        parent_enabled($ifcs; $pppoe_parent_id) as $pppoe_parent_enabled |

        if $current_mtu + $ppoe_eth_overhead > $pppoe_parent_mtu then
            .status.mtu = $pppoe_parent_mtu - $ppoe_eth_overhead
        else
            .
        end |

        if $current_enabled and ($pppoe_parent_enabled | not) then
            .status.enabled = false
        else
            .
        end
    )
'

# Make switched interface standalone if:
#   - it has a VLAN child,
#   - it has a PPPoE child,
#   - it has an IP address assigned (static, dynamic, PD, NDP Proxy); only linkLocal address is ignored.
JQA "${1}" "$DEFS"'
    [.interfaces[]?] as $ifcs |
    [.interfaces[]? | select(is_vlan(.)).vlan.interface.id] as $vlan_parent_ids |
    [.interfaces[]? | select(is_pppoe(.)).pppoe.interface.id] as $pppoe_parent_ids |

    (.interfaces[]? | select(is_switch(.)).switch.ports[]? |
        select(.enabled // false) |
        select(
            (id_in_array(.interface.id; $vlan_parent_ids)) //
            (id_in_array(.interface.id; $pppoe_parent_ids)) //
            has_addr(get_ifc($ifcs; .interface.id))
        )
    ) |= (
        .enabled = false |
        .pvid = null |
        .vid = []
    )
'

# Remove bridged interface from bridge if:
#   - it's switched,
#   - it's bridged by another bridge,
#   - it has an IP address assigned (static, dynamic, PD, NDP Proxy); only linkLocal address is ignored.
JQA "${1}" "$DEFS"'
    [.interfaces[]?] as $ifcs |
    [.interfaces[]? | select(is_switch(.)).switch.ports[]? | select(.enabled) | .interface.id] as $switched_ifcs |

    del(.interfaces[]? |select(is_bridge(.)).bridge.interfaces[]? |
        get_ifc($ifcs; .id) as $bridged_ifc |
        select(
            id_in_array(.id; $switched_ifcs) //
            is_bridge($bridged_ifc) //
            has_addr($bridged_ifc)
        )
    )
'

# Remove aggregated interface from LAG if:
#   - it's aggregated by another LAG,
#   - it has an IP address assigned (static, dynamic, PD, NDP Proxy); only linkLocal address is ignored.
JQA "${1}" "$DEFS"'
    [.interfaces[]?] as $ifcs |

    del(.interfaces[]? | select(is_lag(.)).lag.interfaces[]? |
        get_ifc($ifcs; .id) as $aggregated_ifc |
        select(
            is_lag($aggregated_ifc) //
            has_addr($aggregated_ifc)
        )
    )
'

exit 0
