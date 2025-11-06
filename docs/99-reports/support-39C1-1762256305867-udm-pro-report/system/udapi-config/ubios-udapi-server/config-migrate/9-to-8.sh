#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=8'

# Remove all user <FILTERED> rules. Merging all of them to the main table could cause collisions.
JQA "${1}" 'del(."routes/static"[] |  select(has("table")))'
exit 0
