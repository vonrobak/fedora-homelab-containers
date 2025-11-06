#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."qos/ip"=2'

JQA "${1}" '
if (."qos/ip" != null) then
    if (."qos/ip".queues | length != 0) then
        .qos.ip.queues = ."qos/ip".queues
    else
        .
    end |
    .qos.global.autoRateControl = ."qos/ip".global.autoRateControl |
    if ."qos/ip".global.connectivity then
        .qos.global.connectivity = [."qos/ip".global.connectivity]
    else
        .qos.global.connectivity = [empty]
    end |
    .qos.global.defaultQoSIPQueue = ."qos/ip".global.defaultQoSIPQueue |
    .qos.global.enabled = ."qos/ip".global.enabled |
    del(."qos/ip")
else
    .
end
'

exit 0
