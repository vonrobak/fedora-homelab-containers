#!/usr/bin/env python3

import json
import sys

def add_dslite_capability(interfaces):
    """Add 'dslite' capability to hb46pp interfaces, as capability is introduced in version 33."""
    for interface in interfaces:
        if 'ipv6' not in interface:
            continue

        if 'hb46pp' not in interface['ipv6']:
            continue

        interface['ipv6']['hb46pp']['capability'] = 'dslite'

def handle_auto_remote_addresses(interfaces):
    """Transform auto-* remote addresses to null, and set capability on parent interface's hb46pp."""
    capability_map = {}

    # First pass - identify tunnel interfaces and their capabilities.
    for interface in interfaces:
        if 'tunnel' not in interface:
            continue

        if interface['tunnel']['mode'] != 'ip6tnl':
            continue

        remote = interface['tunnel']['remoteAddress']
        capability = None

        if interface['tunnel']['localAddress']['source'] != 'interface':
            continue

        if remote == 'auto-map-e-hubspoke':
            capability = 'map-e,hubspoke'
            interface['tunnel']['remoteAddress'] = None
        elif remote == 'auto-map-e-jpix':
            capability = 'map-e,jpix'
            interface['tunnel']['remoteAddress'] = None
        elif remote == 'auto-map-e-ntt':
            capability = 'map-e,ntt'
            interface['tunnel']['remoteAddress'] = None

        if capability:
            parent_id = interface['tunnel']['localAddress']['id']
            capability_map[parent_id] = capability

    # Second pass - update parent interfaces with capability.
    for interface in interfaces:
        interface_id = interface['identification']['id']

        if interface_id in capability_map:
            if 'ipv6' not in interface:
                interface['ipv6'] = {}

            if 'hb46pp' not in interface['ipv6']:
                interface['ipv6']['hb46pp'] = {'enabled': True}

            interface['ipv6']['hb46pp']['capability'] = capability_map[interface_id]

if __name__ == '__main__':
    udapi_config_path = sys.argv[1]
    config = json.load(open(udapi_config_path))

    config['versionDetail']['interfaces'] = 33

    if 'interfaces' in config:
        add_dslite_capability(config['interfaces'])
        handle_auto_remote_addresses(config['interfaces'])

    json.dump(config, open(udapi_config_path, 'w'), indent=1)
