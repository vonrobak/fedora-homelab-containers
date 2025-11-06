#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
# update versionDetail
# remove the schedule feature
JQA "${1}" '.versionDetail."firewall/pbr"=6
            |
            ."firewall/pbr".rules|=map(select(.schedule|not))
'

exit 0
