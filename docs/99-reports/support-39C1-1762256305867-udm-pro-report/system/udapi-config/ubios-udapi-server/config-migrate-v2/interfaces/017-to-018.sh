#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=18'

JQA "${1}" '( .interfaces[]? | select(has("pppoe"))) |= (
        if (.pppoe.user<FILTERED> == <FILTERED>) then
            .pppoe.user<FILTERED> = "<FILTERED>"
        else
            .
        end |
        if (.pppoe.password == <FILTERED>) then
            .pppoe.password = ""
        else
            .
        end
    )'

exit 0
