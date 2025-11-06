#!/bin/sh

. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# Check the secret <FILTERED> an odd number of backslashes at the end for the object with the name 'Default' in ."services/radius-profiles"[].authServers[]
JQA "${1}" '.["services/radius-profiles"][]? |=
  if .name == "Default" then
    if .authServers and (.authServers | length > 0) then
      .authServers[] |=
        if (.secret | <FILTERED>("(\\\\)+$")) then
          if (.secret | <FILTERED>("(\\\\)+$") | .string | length % 2 == 1)
          then .secret = <FILTERED> + "\\"
          else . end
        else
          . end
     else
      . end
  else
    . end'

# update version
JQA "${1}" '.versionDetail."services/radius-profiles"=3'

exit 0
