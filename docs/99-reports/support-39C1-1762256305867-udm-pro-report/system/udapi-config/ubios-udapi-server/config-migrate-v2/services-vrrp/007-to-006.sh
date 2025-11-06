#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# Rollback 1. disableInterfacesInBackup 2. garpMasterRepeat 3. garpMasterDelay not supported in v6
JQA "${1}" '
    .versionDetail."services/vrrp"=6 |
    del(.services.vrrp.disableInterfacesInBackup) |
    del(.services.vrrp.garpMasterRepeat) |
    del(.services.vrrp.garpMasterDelay)
'

exit 0
