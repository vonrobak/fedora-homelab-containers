#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."routes/ospf"=4
            |
            del(."routes/ospf".redistributeBGP)'

exit 0
