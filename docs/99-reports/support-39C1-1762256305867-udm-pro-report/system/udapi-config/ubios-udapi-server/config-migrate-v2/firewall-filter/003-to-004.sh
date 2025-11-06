#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# - update feature version
# - move .cathegoryId and .applicationId into .apps array; note that .application Id is optional if .categoryId is set
JQA "${1}" '.versionDetail."firewall/filter"=4 |
	(."firewall/filter"[]?.rules[]? | select(has("categoryId") and has("applicationId"))) |= (. | .apps=[{categoryId, applicationId}] | del(.categoryId, .applicationId)) |
	(."firewall/filter"[]?.rules[]? | select(has("categoryId") and (has("applicationId")|not))) |= (. | .apps=[{categoryId}] | del(.categoryId))'

exit 0
