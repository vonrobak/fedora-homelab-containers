#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=8'

JQA "${1}" '
    def translate_zero_to_null(stmctltype):
        if has("stormControl") then
            if .stormControl[stmctltype] == 0 then
                .stormControl[stmctltype] = null
            else
                .
            end
        else
            .
        end;
    .interfaces[]?.switch.ports[]? |=
        (translate_zero_to_null("multicastRate") |
        translate_zero_to_null("broadcastRate") |
        translate_zero_to_null("unknownUnicastRate"))
'

exit 0
