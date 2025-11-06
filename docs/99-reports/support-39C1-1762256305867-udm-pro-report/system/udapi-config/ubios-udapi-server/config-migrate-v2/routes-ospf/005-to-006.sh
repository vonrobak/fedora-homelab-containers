#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# bump version
JQA "${1}" '.versionDetail."routes/ospf"=6'

exit 0
