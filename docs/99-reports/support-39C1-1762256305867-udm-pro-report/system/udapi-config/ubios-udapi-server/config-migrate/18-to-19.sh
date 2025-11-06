#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=19'

# UTM service - Migrate in steps:

# 1. step: convert all SimpleAddresses to IPAddress

JQA "${1}" '
    def convert_to_ip(simple_address):
        simple_address.address;

    (.services.utm | select(has("dnsFilter")) | .dnsFilter[]? | select(has("dnsAddress")) | .dnsAddress) |= convert_to_ip(.)
    | (.services.utm | select(has("honeypot")) | .honeypot[]? | select(has("ipAddress")) | .ipAddress) |= convert_to_ip(.)
'

# 2. step: convert all Addresses to CIDR

JQA "${1}" '
    def convert_to_cidr(address):
        address.cidr;

    (.services.utm | select(has("dnsFilter")) | .dnsFilter[]? | select(has("netAddresses")) | .netAddresses[]?) |= convert_to_cidr(.)
    | (.services.utm  | select(has("dnsReputation")) | .dnsReputation[]? | select(has("netAddresses")) | .netAddresses[]?) |= convert_to_cidr(.)
'

exit 0

