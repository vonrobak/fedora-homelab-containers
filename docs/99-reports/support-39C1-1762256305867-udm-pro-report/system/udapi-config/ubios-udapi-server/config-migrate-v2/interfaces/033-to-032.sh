#!/usr/bin/env python3

import json
import sys

def remove_capability_field(interfaces):
    """Remove capability field from hb46pp interfaces as it doesn't exist in version 32."""
    for interface in interfaces:
        if 'ipv6' not in interface:
            continue

        if 'hb46pp' not in interface['ipv6']:
            continue

        if 'capability' in interface['ipv6']['hb46pp']:
            del interface['ipv6']['hb46pp']['capability']

def handle_null_remote_addresses(interfaces):
    """Transform null remoteAddress back to auto-* based on parent's hb46pp capability."""
    # First, build a map of interface_id -> capability.
    capability_map = {}
    for interface in interfaces:
        if 'ipv6' not in interface:
            continue

        if 'hb46pp' not in interface['ipv6']:
            continue

        capability_map[interface['identification']['id']] = interface['ipv6']['hb46pp']['capability']

    # Now update the tunnel interfaces.
    for interface in interfaces:
        if 'tunnel' not in interface:
            continue

        if interface['tunnel']['mode'] != 'ip6tnl':
            continue

        if interface['tunnel']['remoteAddress'] is not None:
            continue

        if interface['tunnel']['localAddress']['source'] != 'interface':
            continue

        # The remote address is null, check if the parent interface has a capability.
        parent_id = interface['tunnel']['localAddress']['id']

        if parent_id in capability_map:
            capability = capability_map[parent_id]

            if capability == 'map-e,hubspoke':
                interface['tunnel']['remoteAddress'] = 'auto-map-e-hubspoke'
            elif capability == 'map-e,jpix':
                interface['tunnel']['remoteAddress'] = 'auto-map-e-jpix'
            elif capability == 'map-e,ntt':
                interface['tunnel']['remoteAddress'] = 'auto-map-e-ntt'

if __name__ == '__main__':
    udapi_config_path = sys.argv[1]
    config = json.load(open(udapi_config_path))

    config['versionDetail']['interfaces'] = 32

    if 'interfaces' in config:
        handle_null_remote_addresses(config['interfaces'])
        remove_capability_field(config['interfaces'])

    json.dump(config, open(udapi_config_path, 'w'), indent=1)
