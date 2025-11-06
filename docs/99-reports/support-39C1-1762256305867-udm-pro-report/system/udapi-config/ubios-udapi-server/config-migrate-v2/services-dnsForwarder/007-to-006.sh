#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# Replace the null address with the first IPv4 address from the LAN interface.
# 1. Set versionDetail.services/dnsForwarder = 6.
# 2. Get the list of listenInterfaces from dnsForwarder.
# 3. From the preferred order ["br0", "switch0.1"], pick the first one that matches.
# 4. If br0 and switch0.1 are both not present, pick the first one in the listenInterfaces list.
# 5. Find the matching interface object in the interfaces list.
# 6. Get the first IPv4 address from that interface.
# 7. For each hostRecord:
#    - If .address is null and we have a valid IPv4, add the IPv4 to the record.
#    - If no valid IPv4 is found, remove the record.
#    - Otherwise, leave it as is.
JQA "${1}" '
# Find the interface object by its ID
def find_interface_by_id(id): [.interfaces[]? | select(.identification.id == id)][0]?;

# Find the first IPv4 address from VRRP virtual IPs for a given interface ID
def find_vrrp_ipv4(id):
  [
    .services.vrrp.instances[]?
    | .virtualIPs[]?
    | select(.interface == id)
    | .address
    | select(type == "string")
    | split("/")[0]
  ][0];

# Try to find a valid IPv4 address from the interface or fall back to VRRP
# Returns a plain string like "192.168.1.1"
def find_ipv4_address(id; iface):
  (
    [
      (iface.addresses // [] | .[] | select(.version == "v4" and (.cidr | type == "string")) | .cidr | split("/")[0])
    ][0]
    //
    find_vrrp_ipv4(id)
  );

# Step 1–4: Resolve listenInterfaces → preferred interface ID → interface object → IPv4 address
(.services.dnsForwarder.listenInterfaces // []) as $listen_raw |
($listen_raw | map(.id)) as $listen_ids |
(
  ["br0", "switch0.1"]
  | map(select(. as $x | $listen_ids | index($x)))
) as $preferred_matches |
($preferred_matches[0] // $listen_ids[0] // null) as $selected_id |
(find_interface_by_id($selected_id)) as $interface |
(find_ipv4_address($selected_id; $interface)) as $ipv4 |

# Step 5: Set versionDetail.services/dnsForwarder to 6
.versionDetail."services/dnsForwarder" = 6 |

# Step 6: Update hostRecords
# - If .address is null and a valid IPv4 was found, insert it
# - If no valid IPv4 and .address is null, remove the record
(
  if (.services.dnsForwarder.hostRecords? | type == "array") then
    .services.dnsForwarder.hostRecords |= (
      map(select(
        (.address != null)
        or
        (.address == null and $ipv4 != null)
      ))
      | map(
          if .address == null and $ipv4 != null then
            . + {
              address: {
                address: $ipv4,
                version: "v4"
              }
            }
          else
            .
          end
        )
    )
  else
    .
  end
)
'
exit 0
