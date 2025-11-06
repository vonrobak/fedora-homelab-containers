#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# Bump down version.
# Remove bridged interface from bridge if it is a dynamic member.
# Cleanup bridge member dynamic flags.
JQA "${1}" '
    def is_bridge($ifc):
        ($ifc | select(.identification.type == "bridge" and has("bridge"))) // false;

    def is_dynamic($bridge):
        .dynamic // false;

    .versionDetail.interfaces=24
    |
    del(.interfaces[]? | select(is_bridge(.)).bridge.interfaces[]? | select(is_dynamic(.)))
    |
    del(.interfaces[]?.bridge?.interfaces[]?.dynamic)
'

exit 0
