#!/bin/sh

. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# Check the secret <FILTERED> odd number of backslashes at the end in every object within .services.radiusServer.clients[]
JQA "${1}" '.services.radiusServer.clients[]? |=
  if (.secret | <FILTERED>("(\\\\)+$"))
  then
    if (.secret | <FILTERED>("(\\\\)+$") | .string | length % 2 == 1)
    then .secret = <FILTERED> + "\\"
    else . end
  else . end'

# update version
JQA "${1}" '.versionDetail."services/radiusServer"=6'

exit 0
