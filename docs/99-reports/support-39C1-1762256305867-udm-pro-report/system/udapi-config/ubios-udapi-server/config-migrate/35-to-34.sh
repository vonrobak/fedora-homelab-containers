#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=34'

# Translate dpi config

JQA "${1}" '
if (.services.dpi != null) then
    if (.services.dpi.dpiModule != null) then
        .services.dpi.dpiModuleEnabled = true
    else
        .services.dpi.dpiModuleEnabled = false
    end |
    if (.services.dpi.dpiModule.fingerprinting != null) then
        .services.dpi.fingerprintingEnabled = true
    else
        .services.dpi.fingerprintingEnabled = false
    end |
    if (.services.dpi.dpiModule.fingerprinting.fingerbankAPItoken | <FILTERED>) != 0 then
        .services.dpi.fingerbankAPItoken = <FILTERED>
    else
        .
    end |
    del(.services.dpi.dpiModule)
else
    .
end
'

exit 0
