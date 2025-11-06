#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=42'
JQA "${1}" 'del (."firewall/pbr")'
exit 0
