#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=13'

# When ethernet interface has no poe defined restore it to "off".

JQA "${1}" '(.interfaces[]? | select(has("ethernet")) | .ethernet | select(has("poe") | not)) |= (.poe="off")'

exit 0
