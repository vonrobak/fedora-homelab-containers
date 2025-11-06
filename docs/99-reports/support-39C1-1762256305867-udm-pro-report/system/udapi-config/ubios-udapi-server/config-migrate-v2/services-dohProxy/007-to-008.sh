#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# This config migration is equal to 007-to-006.sh as we are just rolling back the feature.
JQA "${1}" '
  .versionDetail."services/dohProxy" = 8 |

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
