#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=5'
# Move Dynamic DNS client into first entry of client array and add enabled property
JQA "${1}" 'if .services.ddns then .services.ddns = {enabled: .services.ddns.enabled, clients: [.services.ddns | del(.enabled)]} else . end'
