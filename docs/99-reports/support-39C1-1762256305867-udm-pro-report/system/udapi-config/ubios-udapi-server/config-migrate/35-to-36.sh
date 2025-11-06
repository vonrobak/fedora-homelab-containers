#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=36'

# Unsupported speed would be rejected via ethtool/swlib. The only currently valid speed which
# will be rejected in next version is `autodetect` for non-SFP ports. Because UUS behaves the
# same for `autodetect` and `auto` and Unifi devices never use `autodetect`, we can simply change
# all `autodetect` to `auto` (even for SFP ports).
JQA "${1}" '(.interfaces[]? | select(has("status")) | .status | select(has("speed")) | .speed | select(. == "autodetect")) |= "auto"'

exit 0
