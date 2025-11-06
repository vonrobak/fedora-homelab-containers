#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# Convert the version 7 configuration to version 6.
# This script is to keep the first instance of dohProxy if the configuration has multiple instances.
# If the configuration has no dohProxy, it will keep the configuration as it is.
JQA "${1}" '
  .versionDetail."services/dohProxy" = 6 |

  if .services.dohProxy? then
    if (.services.dohProxy.instances // null) != null then
      .services.dohProxy.instances |=
        if length > 0 then [ .[0] | del(.addresses) ] else [] end
    else
      .
    end
  else
    .
  end'
