#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=9'

# Only optional field support was added, no change is needed to upgrade the config.

exit 0

