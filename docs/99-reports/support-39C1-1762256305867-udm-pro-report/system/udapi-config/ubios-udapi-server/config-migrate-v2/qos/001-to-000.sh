#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" 'del(.versionDetail."qos")'

JQA "${1}" '
del(."firewall/mangle"[]?."rules"[]? | select(.target="FW_QOS"))
|
if (."qos" != null) then
    if (.qos.ip.queues | length != 0) then
        ."qos/ip".queues = .qos.ip.queues
    else
        ."qos/ip".queues = [empty]
    end |
    if .qos.global then
        ."qos/ip".global.autoRateControl = .qos.global.autoRateControl |
        ."qos/ip".global.enabled = .qos.global.enabled |
        if (.qos.global.connectivity | length != 0) then
            ."qos/ip".global.defaultQoSIPQueue = .qos.global.defaultQoSIPQueue |
            ."qos/ip".global.connectivity = .qos.global.connectivity[0]
        else
            ."qos/ip".global.defaultQoSIPQueue = null
        end
    else
        .
    end |
    del(.qos)
else
    .
end
'

exit 0
