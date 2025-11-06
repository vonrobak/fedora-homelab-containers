#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."routes/ospf"=3'

exit 0
