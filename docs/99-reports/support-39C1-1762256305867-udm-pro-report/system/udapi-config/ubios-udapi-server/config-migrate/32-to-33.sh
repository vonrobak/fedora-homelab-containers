#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=33'

# 0. common functions

DEF_FUNCS='
  def fix_address:
    if (.type == "static" and has("origin")) then
      .|.origin=null
    else
      .
    end;
'

# 1. Fix static address origin to null in interfaces.addresses[]

JQA "${1}" "${DEF_FUNCS}"'
  (.interfaces[]? | .addresses[]?)
    |= fix_address
'

# 2. Fix static address origin to null in qos/ip.queues[].targetAddresses[]

JQA "${1}" "${DEF_FUNCS}"'
  (."qos/ip" | .queues[]? | .targetAddresses[]?)
    |= fix_address
'

# 3. Fix static address origin to null in services.dhcpServers[].rangeStart

JQA "${1}" "${DEF_FUNCS}"'
  (.services | .dhcpServers[]? | select(has("rangeStart")) | .rangeStart)
    |= fix_address
'

# 4. Fix static address origin to null in services.dhcpServers[].rangeStop

JQA "${1}" "${DEF_FUNCS}"'
  (.services | .dhcpServers[]? | select(has("rangeStop")) | .rangeStop)
    |= fix_address
'

# 5. Fix static address origin to null in system.management.addresses[]

JQA "${1}" "${DEF_FUNCS}"'
  (.system | select(has("management")) | .management | .addresses[]?)
    |= fix_address
'

exit 0
