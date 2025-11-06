#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# Replace empty .instances by null.
JQA "${1}" '
  .versionDetail."services/dohProxy" = 4
  |
  if .services.dohProxy? then
    (.services.dohProxy | select(.instances | length == 0)) |= (.instances |= null)
  else
    .
  end
'

exit 0
