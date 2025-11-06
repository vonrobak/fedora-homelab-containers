#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=33'

# DHCP server - Migrate in steps:

# 1. step: revert all IPAddresses to SimpleAddress

JQA "${1}" '
    def get_version(ip):
        if (ip | contains(":")) then
            "v6"
        else
            "v4"
        end;

    def convert_to_simple(ip):
        {"address": ip,
          "version": get_version(ip)};

    .services.dhcpServers[]?.relay.ipPair[]?.localIp |= convert_to_simple(.)
    | .services.dhcpServers[]?.relay.ipPair[]?.serverIp |= convert_to_simple(.)
    | .services.dhcpServers[]?.activeLeases[]?.address |= convert_to_simple(.)
    | .services.dhcpServers[]?.staticLeases[]?.addresses[]? |= convert_to_simple(.)
    | .services.dhcpServers[]?.dnsServers[]? |= convert_to_simple(.)
    | (.services.dhcpServers[]? | select(has("rangeStart")) | .rangeStart ) |= convert_to_simple(.)
    | (.services.dhcpServers[]? | select(has("rangeStop")) | .rangeStop ) |= convert_to_simple(.)
    | (.services.dhcpServers[]? | select(has("gatewayAddress")) | .gatewayAddress ) |= convert_to_simple(.)
    | (.services.dhcpServers[]? | select(has("dhcpBoot")) | .dhcpBoot.serverIP ) |= convert_to_simple(.)
    | (.services.dhcpServers[]? | select(has("unifiControllerIp")) | .unifiControllerIp ) |= convert_to_simple(.)
'

# 2. step: revert rangeStart and rangeStop to Addresses
#  - add .cidr as .address with prefix (defaulted to 24 resp 64)
#  - remove .address
#  - remove prefix separate field

JQA "${1}" '
    def get_netmask(server):
        if server.ipVersion == "v4" then
            server.ipv4Netmask // 24 | tostring
        else
            server.ipv6PrefixLength // 64 | tostring
        end;

    def remove_netmask(server):
        if server.ipVersion == "v4" then
            del(server.ipv4Netmask)
        else
            del(server.ipv6PrefixLength)
        end;

    def convert_to_address(address):
        (address.cidr = (address.address + "/" + get_netmask(.))
        | del(address.address));

    def migrate_dhcp_server:
        . | convert_to_address(.rangeStart)
          | ((select(has("rangeStop")) | convert_to_address(.rangeStop) )
            // .)
          | remove_netmask(.);

    (.services.dhcpServers[]? | select(has("rangeStart")))
        |= (. | migrate_dhcp_server)
'

exit 0
