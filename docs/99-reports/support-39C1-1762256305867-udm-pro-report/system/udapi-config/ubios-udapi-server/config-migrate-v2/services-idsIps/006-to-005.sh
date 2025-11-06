#!/usr/bin/env python3

import json
import sys


def make_interface_dict(interface_id: str) -> dict:
    return {
        "id": interface_id,
    }


def get_interfaces_list_from_vrrp(vrrp: dict) -> dict:
    if not vrrp:
        return {}
    interfaces_list = {}
    for instance in vrrp.get("instances", []):
        for virtual_ip in instance.get("virtualIPs", []):
            interface = virtual_ip.get("interface", None)
            address = virtual_ip.get("address", None)
            if interface and address:
                if not interfaces_list.get(interface, None):
                    interfaces_list[interface] = set()
                interfaces_list[interface].add(address)
    return interfaces_list


def list_selected_interfaces(config: dict) -> list[dict]:
    interfaces = config.get("interfaces", [])
    vrrp = config.get("services", {}).get("vrrp", {})
    vrrp_interfaces_list = get_interfaces_list_from_vrrp(vrrp)
    idsIps_netAddresses = set(
        config.get("services", {}).get("idsIps", {}).get("netAddresses", [])
    )

    selected_interface_ids = set()
    for interface in interfaces:
        interface_id = interface.get("identification", {}).get("id", None)
        if (
            len(
                idsIps_netAddresses
                & {
                    address.get("cidr", None)
                    for address in interface.get("addresses", [])
                    if address.get("origin", None) not in ["linkLocal", "vrrp"]
                }
            )
            > 0
        ):
            selected_interface_ids.add(interface_id)
        if (
            "vrrp"
            in {
                address.get("origin", None)
                for address in interface.get("addresses", [])
            }
            or len(idsIps_netAddresses & vrrp_interfaces_list.get(interface_id, set()))
            > 0
        ):
            selected_interface_ids.add(interface_id)

    selected_interface_ids.discard(None)
    return list(map(make_interface_dict, sorted(list(selected_interface_ids))))


def migrate_ids_ips(config: dict):
    config["versionDetail"]["services/idsIps"] = 5
    if not config.get("services", {}).get("idsIps", None):
        return
    config["services"]["idsIps"]["interfaces"] = list_selected_interfaces(config)
    config["services"]["idsIps"].pop("netAddresses", None)


if __name__ == "__main__":
    udapi_config_path = sys.argv[1]
    config = json.load(open(udapi_config_path))
    migrate_ids_ips(config)
    json.dump(config, open(udapi_config_path, "w"), indent=1)
