#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

JQA "${1}" '
  .versionDetail."services/dohProxy" = 7'
