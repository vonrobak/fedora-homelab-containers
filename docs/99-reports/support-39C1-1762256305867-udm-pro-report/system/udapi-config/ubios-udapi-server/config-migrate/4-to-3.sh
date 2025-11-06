#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=3'
# Null .origin field can be referenced either from Address or SimpleAddress schemas, both have .version and (.cidr or .address) properties required.
# If such object is found and .origin is set to null, .origin is deleted.
JQA "${1}" '(..|objects|select(has("origin") and has("version") and (has("cidr") or has("address")))) |= if (.origin == null) then del(.origin) else . end'
# Non-mandatory .type field can be referenced from Address schema which has .version and .cidr properties required.
# If such object is found and .type is missing, .type is deduced from .cidr value (i.e. set to "dynamic", if .cidr is equal to null; otherwise, set to "static")
JQA "${1}" '(..|objects|select(has("version") and has("cidr") and (has(type) | not))) |= if (.cidr == null) then .type="dynamic" else .type="static" end'
