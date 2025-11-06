#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."firewall/filter"=2'

JQA "${1}" '(."firewall/filter"[]."rules"[] | select(has("source") or has("destination")) | (.source,.destination) | select(has("sets") and has("address"))) |= (.sets=[])'

exit 0
