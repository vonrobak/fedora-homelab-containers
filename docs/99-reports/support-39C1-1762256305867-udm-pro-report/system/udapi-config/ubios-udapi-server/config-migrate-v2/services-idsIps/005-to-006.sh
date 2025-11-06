#!/usr/bin/env python3

import json
import sys
from typing import Optional


def get_cidr_from_vrrp(vrrp: dict, interface_ids: Optional[str]) -> list[str]:
    if not vrrp or not interface_ids or vrrp == {} or not vrrp.get("enabled", False):
        return []
    selected_cidrs = set()
    for instance in vrrp.get("instances", []):
        selected_cidrs |= {
            virtual_ip.get("address", None)
            for virtual_ip in instance.get("virtualIPs", [])
            if virtual_ip.get("interface", None) == interface_ids
        }
    selected_cidrs.discard(None)
    return selected_cidrs


def list_selected_netAddresses(config: dict) -> list[str]:
    interfaces = config.get("interfaces", [])
    idsIps = config.get("services", {}).get("idsIps", {})
    vrrp = config.get("services", {}).get("vrrp", {})
    selected_interface_ids = {
        interface.get("id", None) for interface in idsIps.get("interfaces", [])
    }
    selected_interface_ids.discard(None)

    selected_cidrs = set()
    for interface in interfaces:
        if (
            interface.get("identification", {}).get("id", None)
            not in selected_interface_ids
        ):
            continue
        selected_cidrs |= {
            address.get("cidr", None)
            for address in interface.get("addresses", [])
            if address.get("origin", None) not in ["linkLocal", "vrrp"]
        }
        if "vrrp" in {
            address.get("origin", None) for address in interface.get("addresses", [])
        }:
            selected_cidrs |= get_cidr_from_vrrp(
                vrrp, interface.get("identification", {}).get("id", None)
            )
    selected_cidrs.discard(None)
    return sorted(list(selected_cidrs))


def migrate_ids_ips(config: dict):
    config["versionDetail"]["services/idsIps"] = 6
    if not config.get("services", {}).get("idsIps", None):
        return
    config["services"]["idsIps"]["netAddresses"] = list_selected_netAddresses(config)
    config["services"]["idsIps"].pop("interfaces", None)


if __name__ == "__main__":
    udapi_config_path = sys.argv[1]
    config = json.load(open(udapi_config_path))
    migrate_ids_ips(config)
    json.dump(config, open(udapi_config_path, "w"), indent=1)
