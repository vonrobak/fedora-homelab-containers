#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# - update feature version
# - move .cathegoryId and .applicationId into .apps array; note that .application Id is optional if .categoryId is set
JQA "${1}" '.versionDetail."firewall/mangle"=6 |
	(."firewall/mangle"[]?.rules[]? | select(has("categoryId") and has("applicationId"))) |= (. | .apps=[{categoryId, applicationId}] | del(.categoryId, .applicationId)) |
	(."firewall/mangle"[]?.rules[]? | select(has("categoryId") and (has("applicationId")|not))) |= (. | .apps=[{categoryId}] | del(.categoryId))'

exit 0
