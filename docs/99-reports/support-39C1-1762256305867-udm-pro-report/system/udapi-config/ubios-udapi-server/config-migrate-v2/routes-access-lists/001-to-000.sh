#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" 'del(.versionDetail."routes/access-lists")'
JQA "${1}" 'del(."routes/access-lists")'

exit 0
