#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=35'

# Translate dpi config

JQA "${1}" '
    if (.services.dpi.dpiModuleEnabled == true) then
        .services.dpi.dpiModule = {} |
        if (.services.dpi.fingerprintingEnabled == true) then
            .services.dpi.dpiModule.fingerprinting.wifiListener.address = "192.168.1.1" |
            .services.dpi.dpiModule.fingerprinting.wifiListener.port = 10101 |
            .services.dpi.dpiModule.fingerprinting.wifiListener.key = "<FILTERED>" |
            if (.services.dpi.fingerbankAPItoken | <FILTERED>) != 0 then
                .services.dpi.dpiModule.fingerprinting.fingerbankAPItoken = <FILTERED>
            else
                .
            end
        else
            .
        end
    else
        .
    end |
    del(.services.dpi.fingerprintingEnabled) |
    del(.services.dpi.fingerbankAPIToken) |
    del(.services.dpi.dpiModuleEnabled) 
'

exit 0
