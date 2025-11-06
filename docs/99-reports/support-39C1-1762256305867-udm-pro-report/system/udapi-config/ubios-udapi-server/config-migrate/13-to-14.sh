#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=14'

# remove PoE set to "off", because it is defined also for interfaces that has no PoE at all.
# PoE that was off stays off even when no value is defined in the config

JQA "${1}" '(.interfaces[]? | select(has("ethernet")) | .ethernet | select(has("poe"))) |= (if .poe | contains("off") then del(.poe) else . end)'

exit 0
