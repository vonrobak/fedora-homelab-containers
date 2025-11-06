#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/ddns"=1'

# Remove all ddns clients where service=="cloudflare"
JQA "${1}" '(.services.ddns.clients | arrays ) |= map(select(.service != "cloudflare"))'

exit 0
