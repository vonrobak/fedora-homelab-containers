#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/openvpn/raws"=2'


ENABLED=`jq -r '."vpn/openvpn/raws" | length' "${1}"`
if [ ${ENABLED} -eq 0 ] ; then
    exit 0
fi

ROUTING_ID=$((`jq -r '[.services.wanFailover.wanInterfaces[]?.routingTable] | max' "${1}"` + 1))
RAW_ID=`jq -r '[."vpn/openvpn/raws"[]?.id] | max' "${1}"`
IF_NAME="tunovpnc$RAW_ID"
FW_PBR_RULE_ID=$((`jq -r '[."firewall/pbr".rules[]?.id] | max' "${1}"` + 1))

JQA "${1}" '.services.wanFailover.wanInterfaces += [{"interface": $ifname,
                                                     "metric": 230,
                                                     "routingTable": $rid
                                                   }]' "--arg ifname ${IF_NAME} --argjson rid ${ROUTING_ID}"

JQA "${1}" '."firewall/pbr".rules += [{"id": $pbr_id,
                                       "trafficType": "forwarded",
                                       "routingMode": {"mode": "table", "pbrTable": $rid},
                                       "source": {"sets": ["local_network"] }
                                      }]' "--argjson pbr_id ${FW_PBR_RULE_ID} --argjson rid ${ROUTING_ID}"

FW_PBR_RULE_ID=$((FW_PBR_RULE_ID+1))
JQA "${1}" '."firewall/pbr".rules += [{"id": $pbr_id,
                                       "trafficType": "local",
                                       "routingMode": {"mode": "table", "pbrTable": $rid}
                                      }]' "--argjson pbr_id ${FW_PBR_RULE_ID} --argjson rid ${ROUTING_ID}"

exit 0
