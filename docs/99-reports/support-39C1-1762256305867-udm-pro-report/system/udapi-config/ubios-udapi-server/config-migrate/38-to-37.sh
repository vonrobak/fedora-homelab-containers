#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=37'

# services.dnsForwarder.preauthSites were not actually working in version 37
# see here https://github.com/ubiquiti/ubios-udapi-server/pull/1083#discussion_r455253391
JQA "${1}" 'del(.services.dnsForwarder.ipsets)'

exit 0
