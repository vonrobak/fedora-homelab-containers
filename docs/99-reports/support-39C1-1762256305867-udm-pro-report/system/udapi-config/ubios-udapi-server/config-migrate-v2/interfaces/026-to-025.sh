#!/usr/bin/env python3

import json
import sys

def delete_hb46pp(interface):
    if 'ipv6' in interface:
        if 'hb46pp' in interface['ipv6']:
            del interface['ipv6']['hb46pp']
    return interface

def migrate_ip6tnl(interface):
    if 'tunnel' in interface:
        if interface['tunnel']['mode'] == 'ip6tnl':
            if interface['tunnel']['remoteAddress'] is None:
                interface['tunnel']['remoteAddress'] = 'auto'
            if 'remoteAddressFallbackMapping' in interface['tunnel']:
                del interface['tunnel']['remoteAddressFallbackMapping']
    return interface

if __name__ == '__main__':
    udapi_config_path = sys.argv[1]
    config = json.load(open(udapi_config_path))
    config['versionDetail']['interfaces'] = 25
    if 'interfaces' in config:
        config['interfaces'] = [delete_hb46pp(intf)  for intf in config['interfaces']]
        config['interfaces'] = [migrate_ip6tnl(intf) for intf in config['interfaces']]
    json.dump(config, open(udapi_config_path, 'w'), indent=1)
