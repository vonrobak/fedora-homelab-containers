#!/usr/bin/env python3

import json
import sys

"""
Move the CIDR representing the Interface in netAddresses to the new interfaces field
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
            cidr_config.update(
                {
                    cidr: interface_id,
                }
            )
    return cidr_config


def get_cidr_config_from_interfaces(interfaces: list[dict]) -> dict:
    if not interfaces or len(interfaces) == 0:
        return dict()
    cidr_config = dict()

    for interface in interfaces:
        interface_id = interface.get("identification", {}).get("id", None)
        if not interface_id:
            continue
        for address in interface.get("addresses", []):
            cidr = address.get("cidr", None)
            if not cidr:
                continue
            cidr_config.update(
                {
                    cidr: interface_id,
                }
            )
    return cidr_config


def get_cidr_config(config: dict) -> dict:
    cidr_config = dict()
    cidr_config.update(
        get_cidr_config_from_vrrp(config.get("services", {}).get("vrrp", {}))
    )
    cidr_config.update(get_cidr_config_from_interfaces(config.get("interfaces", [])))
    return cidr_config


def convert_netAddresses_to_interfaces(item: dict, cidr_config: dict):
    item["interfaces"] = list()

    netAddresses = item.get("netAddresses", [])
    netAddresses_len = len(netAddresses)
    if netAddresses_len == 0:
        return

    interfaces = set()
    for i in range(netAddresses_len - 1, -1, -1):
        interface_id = cidr_config.get(netAddresses[i], None)
        if not interface_id:
            continue
        netAddresses.pop(i)
        if interface_id not in interfaces:
            interfaces.add(interface_id)
            item["interfaces"].append(interface_id)
    item["interfaces"].sort()
    return


def migrate_utm(config: dict):
    config["versionDetail"]["services/utm"] = 4
    if not config.get("services", {}).get("utm", None):
        return
    cidr_config = get_cidr_config(config)

    for item in config.get("services", {}).get("utm", {}).get("dnsFilter", []):
        convert_netAddresses_to_interfaces(item, cidr_config)
    for item in config.get("services", {}).get("utm", {}).get("dnsReputation", []):
        convert_netAddresses_to_interfaces(item, cidr_config)


if __name__ == "__main__":
    udapi_config_path = sys.argv[1]
    config = json.load(open(udapi_config_path))
    migrate_utm(config)
    json.dump(config, open(udapi_config_path, "w"), indent=1)
