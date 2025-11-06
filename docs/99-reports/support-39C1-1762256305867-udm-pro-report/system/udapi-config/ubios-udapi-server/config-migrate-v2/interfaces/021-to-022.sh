#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."interfaces"=22'

# Remove localhost IPv6 address if present to prevent duplicate addresses.
JQA "${1}" '(.interfaces[]? | select(.identification.id=="lo").addresses[]? | select(.cidr=="::1/128")) |= empty'

# Add localhost IPv6 address to loopback interface.
JQA "${1}" '(.interfaces[]? | select(.identification.id=="lo").addresses) |= . + [{"type": "static", "cidr": "::1/128", "version": "v6"}]'

exit 0
