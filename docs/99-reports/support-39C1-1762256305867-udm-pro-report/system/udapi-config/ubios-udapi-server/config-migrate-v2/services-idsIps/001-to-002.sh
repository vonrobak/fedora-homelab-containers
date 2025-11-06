#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

x=`jq -c '.services.idsIps?.signature<FILTERED>[]?' "${1}" |wc -l `
mode=`jq -cr '.services.idsIps?.mode' "${1}"`
action='alert'
if [ "$mode" = "pcap-l3-blocking-high" ]
then
    action='block'
fi
while [ $x -gt 0 ]
do
    x=$(($x-1))
    category=`jq -c ".services.idsIps?.signature<FILTERED>[${x}]" "${1}"`
    JQA "${1}" '.services.idsIps.signature<FILTERED>[$id]|={"category": $category, "action": $action}' "--argjson id ${x} --arg action ${action} --argjson category ${category}"
done

JQA "${1}" '.versionDetail."services/idsIps"=2'

exit 0
