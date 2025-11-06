#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# Dummy version bump to let NET know that UXG-3518 has been fixed
JQA "${1}" '.versionDetail."services/vrrp"=5 | .versionFormat="v2"'

exit 0
