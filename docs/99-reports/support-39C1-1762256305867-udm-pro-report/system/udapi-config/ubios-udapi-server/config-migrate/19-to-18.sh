#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=18'

# UTM service - Migrate in steps:

# 1. step: revert all IPAddresses to SimpleAddress

JQA "${1}" '
    def get_version(ip):
        if (ip | contains(":")) then
            "v6"
        else
            "v4"
        end;

    def convert_to_simple_address(ip):
        {"address": ip,
         "type": "static",
         "version": get_version(ip)};

    (.services.utm | select(has("dnsFilter")) | .dnsFilter[]? | select(has("dnsAddress")) | .dnsAddress) |= convert_to_simple_address(.)
    | (.services.utm | select(has("honeypot")) | .honeypot[]? | select(has("ipAddress")) | .ipAddress) |= convert_to_simple_address(.)
'

# 2. step: revert all CIDRs to Address

JQA "${1}" '
    def get_version(cidr):
        if (cidr | contains(":")) then
            "v6"
        else
            "v4"
        end;

    def convert_to_address(cidr):
        {"cidr": cidr,
         "type": "static",
         "version": get_version(cidr)};

    (.services.utm | select(has("dnsFilter")) | .dnsFilter[]? | select(has("netAddresses")) | .netAddresses[]?) |= convert_to_address(.)
    | (.services.utm  | select(has("dnsReputation")) | .dnsReputation[]? | select(has("netAddresses")) | .netAddresses[]?) |= convert_to_address(.)
'

exit 0
