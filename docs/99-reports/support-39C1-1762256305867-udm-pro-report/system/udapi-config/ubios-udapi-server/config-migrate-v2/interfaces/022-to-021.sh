#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=21'

# Do NOT remove localhost IPv6 address as we don't know whether it was provisioned or added by migration script.

exit 0
