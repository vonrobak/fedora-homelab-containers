#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=11'

# Remove fingerbankAPItoken <FILTERED>
JQA "${1}" 'del(.services.dpi?.fingerbankAPIToken)'

exit 0
