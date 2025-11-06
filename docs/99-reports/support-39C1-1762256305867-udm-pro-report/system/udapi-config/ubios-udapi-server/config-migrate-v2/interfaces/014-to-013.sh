#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=13'

JQA "${1}" '(.interfaces[]? | .status.speed | select(.=="25000-full")) |= "auto"'

exit 0
