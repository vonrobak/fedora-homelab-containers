#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# 1. Set versionDetail.services/dnsForwarder = 7.
# 2. Get all IPv4 addresses from interface "br0".
# 3. For each hostRecord:
#    - If .address matches any of the br0 IPv4 addresses, set .address = null and remove .ttl.
#    - Otherwise, leave it as is.
JQA "${1}" '
    # Extract all IPv4 addresses from br0 (CIDR prefix only)
    def get_br0_ipv4_list:
    (
        [
            .interfaces[]?
            | select(.identification.id == "br0")
            | .addresses[]?
            | select(.version == "v4" and (.cidr | type == "string"))
            | .cidr
            | split("/")[0]
        ]
        +
        [
            .services.vrrp.instances[]?
            | .virtualIPs[]?
            | select(.interface == "br0")
            | .address
            | select(type == "string")
            | split("/")[0]
        ]
    );

    get_br0_ipv4_list as $ipv4_list
    | .versionDetail."services/dnsForwarder" = 7
    | if (.services.dnsForwarder.hostRecords? | type == "array") then
        .services.dnsForwarder.hostRecords |= map(
            (
                .address.address as $addr
                | if ($ipv4_list | index($addr)) and (.hostName | startswith("*.") | not) then
                    .address = null | del(.ttl)
                  else
                    .
                  end
            )
        )
      else
        .
      end
'
exit 0
