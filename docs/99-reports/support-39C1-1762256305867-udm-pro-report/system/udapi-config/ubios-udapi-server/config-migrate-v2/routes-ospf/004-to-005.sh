#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."routes/ospf"=5
            |
            if .["routes/ospf"] then
              .["routes/ospf"] += {redistributeBGP: {}}
            else
              .
            end
'

exit 0
