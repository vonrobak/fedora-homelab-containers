#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/dohProxy"=3'

# Replace null .instances by empty array.
JQA "${1}" '(.services.dohProxy | select(.instances == null)) |= (.instances |= [])'

exit 0
