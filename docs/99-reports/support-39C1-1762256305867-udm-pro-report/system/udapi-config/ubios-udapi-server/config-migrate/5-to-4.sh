#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=4'
# Move first client to top level ddns object
JQA "${1}" 'if .services.ddns then .services.ddns = .services.ddns.clients[0] + {enabled: .services.ddns.enabled } else . end'
