#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=38'

# services.dnsForwarder.preauthSites were hardcoded to guest_allowed_ip IP set
JQA "${1}" '
    (.services.dnsForwarder | select (has("preauthSites") and (.preauthSites | length) > 0))
        |= (. + {"ipsets": [{"ipsets": ["guest_allowed_ip"], "hosts": .preauthSites}]})
    | del(.services.dnsForwarder.preauthSites)'

exit 0
