#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=32'

# change hardcoded factory-default UUID to null for UNMS-R-Pro and UNMS-R-Lite

JQA "${1}" '
    if .services.bleHTTPTransport.serviceUUID == "8f30f895-c8e7-463e-9c5c-91b29b3f139e" or
       .services.bleHTTPTransport.serviceUUID == "fbfc5eda-440a-4efd-a022-ef7646f8aef5" then
        .services.bleHTTPTransport.serviceUUID = null
    else
        .
    end'

exit 0
