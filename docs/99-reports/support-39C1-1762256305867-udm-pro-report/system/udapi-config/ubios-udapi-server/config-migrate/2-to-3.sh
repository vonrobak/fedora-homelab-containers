#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=3'
JQA "${1}" '.interfaces[] .addresses[]? |= if (.cidr == null or .cidr == "") then .cidr=null else . end'
