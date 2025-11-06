#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/dohProxy"=2'
JQT "${1}" '.services.dohProxy.enabled' || exit 0
JQT "${1}" '.services.dohProxy.instances[]?' || exit 0

JQA "${1}" '.services.dohProxy.instances[].servers |= map(.server)'
exit 0

