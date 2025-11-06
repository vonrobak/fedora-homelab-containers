#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

x=`jq -c '.services.idsIps?.signature<FILTERED>[]?' "${1}" |wc -l `
while [ $x -gt 0 ]
do
    x=$(($x-1))
    category=`jq -cr ".services.idsIps?.signature<FILTERED>[${x}].category" "${1}"`
    JQA "${1}" '.services.idsIps.signature<FILTERED>[$id]|=$category' "--argjson id ${x} --arg category ${category}"
done

JQA "${1}" '.versionDetail."services/idsIps"=1'

exit 0
