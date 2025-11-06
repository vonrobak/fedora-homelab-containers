#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=34'

# DHCP server - Migrate in steps:

# 1. step: make rangeStart and rangeStop SimpleAddresses
#  - remove .cidr
#  - add .address without prefix
#  - add prefix as a separate field

JQA "${1}" '
    def parse_address(address):
        address.cidr | split("/")[0];

    def parse_netmask(address):
        address.cidr | split("/")[1] | tonumber;

    def add_netmask(server):
        if server.ipVersion == "v4" then
            (server.ipv4Netmask = (parse_netmask(server.rangeStart)))
        else
            (server.ipv6PrefixLength = (parse_netmask(server.rangeStart)))
        end;

    def convert_to_simple(address):
        (address.address = (parse_address(address))
        | del(address.cidr)
        | del(address.eui64?)
        | del(address.comment?));

    def migrate_dhcp_server:
        . | add_netmask(.)
          | convert_to_simple(.rangeStart)
          | ((select(has("rangeStop")) | convert_to_simple(.rangeStop) )
            // .);

    (.services.dhcpServers[]? | select(has("rangeStart")))
        |= (. | migrate_dhcp_server)
'

# 2. step: convert all SimpleAddresses to IPAddress

JQA "${1}" '
    def convert_to_ip(simple):
        simple.address;

    .services.dhcpServers[]?.relay.ipPair[]?.localIp |= convert_to_ip(.)
    | .services.dhcpServers[]?.relay.ipPair[]?.serverIp |= convert_to_ip(.)
    | .services.dhcpServers[]?.activeLeases[]?.address |= convert_to_ip(.)
    | .services.dhcpServers[]?.staticLeases[]?.addresses[]? |= convert_to_ip(.)
    | .services.dhcpServers[]?.dnsServers[]? |= convert_to_ip(.)
    | (.services.dhcpServers[]? | select(has("rangeStart")) | .rangeStart ) |= convert_to_ip(.)
    | (.services.dhcpServers[]? | select(has("rangeStop")) | .rangeStop ) |= convert_to_ip(.)
    | (.services.dhcpServers[]? | select(has("gatewayAddress")) | .gatewayAddress ) |= convert_to_ip(.)
    | (.services.dhcpServers[]? | select(has("dhcpBoot")) | .dhcpBoot.serverIP ) |= convert_to_ip(.)
    | (.services.dhcpServers[]? | select(has("unifiControllerIp")) | .unifiControllerIp ) |= convert_to_ip(.)
'

# SimpleAddress has required .version field; DnsForwarder service is missing it

JQA "${1}" '
    def add_version:
        if (.address | contains(":")) then
            (.version = "v6")
        else
            (.version = "v4")
        end;

    .services.dnsForwarder.hostRecords[]?.address |= (. | add_version)
'

exit 0

