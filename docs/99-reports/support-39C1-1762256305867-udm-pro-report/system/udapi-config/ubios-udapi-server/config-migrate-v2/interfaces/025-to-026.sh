#!/usr/bin/env python3

import json
import sys

def migrate_ip6tnl(interface):
    if 'tunnel' in interface:
        if interface['tunnel']['mode'] == 'ip6tnl':
            if interface['tunnel']['remoteAddress'].lower() == 'auto':
                interface['tunnel']['remoteAddress'] = None
                interface['tunnel']['remoteAddressFallbackMapping'] = [
                    {
                        "localAddressPrefix": "2409:10::/30",
                        "remoteAddress": "aftr.transix.jp"
                    },
                    {
                        "localAddressPrefix": "2409:250::/30",
                        "remoteAddress": "aftr.transix.jp"
                    }
                ]
    return interface

def is_auto_ip6tnl(interface):
    if 'tunnel' in interface:
        if interface['tunnel']['mode'] == 'ip6tnl':
            if interface['tunnel']['remoteAddress'] == None:
                if interface['tunnel']['localAddress']['source'] == 'interface':
                    return True;
    return False


def add_hb46pp(interfaces):
    for interface in interfaces:
        if is_auto_ip6tnl(interface):
            parent_id = interface['tunnel']['localAddress']['id']
            for parent_interface in interfaces:
                if parent_interface['identification']['id'] == parent_id:
                    if 'ipv6' not in parent_interface:
                        parent_interface['ipv6'] = {}
                    parent_interface['ipv6']['hb46pp'] = { 'enabled': True }
                    break

if __name__ == '__main__':
    udapi_config_path = sys.argv[1]
    config = json.load(open(udapi_config_path))
    config['versionDetail']['interfaces'] = 26
    if 'interfaces' in config:
        config['interfaces'] = [migrate_ip6tnl(intf) for intf in config['interfaces']]
        add_hb46pp(config['interfaces'])
    json.dump(config, open(udapi_config_path, 'w'), indent=1)
