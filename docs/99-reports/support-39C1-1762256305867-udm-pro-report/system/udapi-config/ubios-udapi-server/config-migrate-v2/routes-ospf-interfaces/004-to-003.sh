#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# bump version
# cleanup interfaces of not supported network type:
#   - only "auto" and "point-to-point" are effective in v3
#   - "broadcast" was never applicable to configuration before v4
JQA "${1}" '.versionDetail."routes/ospf/interfaces"=3
            |
            del(."routes/ospf/interfaces"[]? | select(has("network") and .network != "auto" and .network != "point-to-point"))
'

exit 0
