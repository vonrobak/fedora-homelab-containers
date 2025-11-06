#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=7'

JQA "${1}" '
    def translate_null_to_zero(stmctltype):
        if has("stormControl") then
            .stormControl |=
            if has(stmctltype) and .[stmctltype] == null then
                .[stmctltype] = 0
            else
                .
            end
        else
            .
        end;
    .interfaces[]?.switch.ports[]? |=
        (translate_null_to_zero("multicastRate") |
        translate_null_to_zero("broadcastRate") |
        translate_null_to_zero("unknownUnicastRate"))
'

exit 0
