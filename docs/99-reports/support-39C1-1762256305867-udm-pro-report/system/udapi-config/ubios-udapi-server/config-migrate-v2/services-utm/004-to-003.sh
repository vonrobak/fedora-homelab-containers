#!/usr/bin/env python3

import json
import sys

"""
Move the iface in the interfaces field to the CIDR field and remove the interfaces field
"""


def get_cidr_config_from_vrrp(vrrp: dict) -> dict:
    if not vrrp or not vrrp.get("enabled", False):
        return dict()
    cidr_config = dict()
    for instance in vrrp.get("instances", []):
        for virtualIP in instance.get("virtualIPs", []):
            interface_id = virtualIP.get("interface", None)
            cidr = virtualIP.get("address", None)
            if not interface_id or not cidr:
                continue
            if interface_id not in cidr_config:
                cidr_config[interface_id] = []
            cidr_config[interface_id].append(cidr)
    return cidr_config


def get_cidr_config_from_interfaces(interfaces: list[dict]) -> dict:
    if not interfaces or len(interfaces) == 0:
        return dict()
    cidr_config = dict()

    for interface in interfaces:
        interface_id = interface.get("identification", {}).get("id", None)
        if not interface_id:
            continue
        cidrs = []
        for address in interface.get("addresses", []):
            cidr = address.get("cidr", None)
            if not cidr:
                continue
            cidrs.append(cidr)
        cidr_config.update(
            {
                interface_id: cidrs,
            }
        )
    return cidr_config


def get_cidr_config(config: dict) -> dict:
    vrrp_config = get_cidr_config_from_vrrp(config.get("services", {}).get("vrrp", {}))
    interfaces_config = get_cidr_config_from_interfaces(config.get("interfaces", []))

    for interface_id, cidrs in vrrp_config.items():
        if interface_id not in interfaces_config:
            interfaces_config[interface_id] = []
        interfaces_config[interface_id] += cidrs
    return interfaces_config


def convert_interfaces_to_netAddresses(item: dict, cidr_config: dict):
    if "interfaces" not in item:
        return

    if "netAddresses" not in item:
        item["netAddresses"] = []
    for interface_id in item["interfaces"]:
        item["netAddresses"] += cidr_config.get(interface_id, [])
    item["netAddresses"] = list(set(item["netAddresses"]))
    item["netAddresses"].sort()
    item.pop("interfaces", None)
    return


def migrate_utm(config: dict):
    config["versionDetail"]["services/utm"] = 3
    if not config.get("services", {}).get("utm", None):
        return
    cidr_config = get_cidr_config(config)

    for item in config.get("services", {}).get("utm", {}).get("dnsFilter", []):
        convert_interfaces_to_netAddresses(item, cidr_config)
    for item in config.get("services", {}).get("utm", {}).get("dnsReputation", []):
        convert_interfaces_to_netAddresses(item, cidr_config)


if __name__ == "__main__":
    udapi_config_path = sys.argv[1]
    config = json.load(open(udapi_config_path))
    migrate_utm(config)
    json.dump(config, open(udapi_config_path, "w"), indent=1)
