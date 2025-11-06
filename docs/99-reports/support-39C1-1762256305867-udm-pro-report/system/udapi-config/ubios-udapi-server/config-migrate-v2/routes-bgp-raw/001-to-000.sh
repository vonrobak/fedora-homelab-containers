#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" 'del(.versionDetail."routes/bgp/raw")
            |
            del(."routes/bgp/raw")
'

exit 0
