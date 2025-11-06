#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/radius-profiles"=1'

# delete unused attributes
JQA "${1}" '
    (. | select(has("services")) | .services | select(has("radius-profiles")) | ."radius-profiles"[]?) |= (
        del(.serviceType)
    )
'

exit 0
