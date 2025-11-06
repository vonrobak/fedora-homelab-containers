#!/bin/sh
. "$(dirname "${0}")"/../JQ

JQA "${1}" '.versionDetail."interfaces"=19'
JQA "${1}" 'del(.interfaces[]? | select(.ethernet.sfp.fec != null).ethernet.sfp)'
