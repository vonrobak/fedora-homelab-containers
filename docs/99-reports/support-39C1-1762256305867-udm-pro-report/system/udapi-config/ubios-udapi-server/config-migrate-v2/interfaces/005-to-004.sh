#!/usr/bin/env python3

import sys
import json
from os import path
from collections import defaultdict

sys.path.append(path.join(path.dirname(__file__),'..'))
from udapi_server import get_board_config_path, BRIDGE_PREFIX, SWITCH_PREFIX

class SwitchPort:
    def __init__(self, switch_port):
        self.ifc_id = switch_port['interface']['id']
        self.pvid = switch_port.get('pvid', None)
        self.vlans = switch_port.get('vid', [])

class Migration:
    '''
    Migrate switch0-based to standalone-ports-based interface config.
    '''
    def __init__(self, board_config):
        self.board_config = board_config
        self.max_mtu = 1500

    def check_interface(self, interface, tagged, untagged):
        '''
        Filter for interface list.
        Modifies bridge contents to fill it with interfaces
        matching switch configuration.
        Return value indicates whether given interface should be kept
        in the interface list (True) or removed (False).
        '''
        identification = interface['identification']
        ifc_id = identification['id']

        if identification['type'] == 'switch':
            return False

        if identification['type'] == 'vlan':
            base_ifc_id = interface['vlan']['interface']['id']
            if base_ifc_id.startswith(SWITCH_PREFIX):
                mtu = interface.get('status',{}).get('mtu', None)
                if mtu is not None and mtu > self.max_mtu:
                    self.max_mtu = mtu
                return False
            return True

        if identification['type'] == 'bridge' and ifc_id.startswith(BRIDGE_PREFIX):
            bridge_vid = int(ifc_id[len(BRIDGE_PREFIX):])
            # br0 stands for vlan 1
            if bridge_vid == 0:
                bridge_vid = 1

            interface['bridge']['interfaces'] = [
                {'id': ifc_id} for ifc_id in untagged[bridge_vid]
            ] + [
                {'id':'{}.{}'.format(ifc_id, bridge_vid)}
                for ifc_id in tagged[bridge_vid]
            ] + [
                name for name
                in interface['bridge']['interfaces']
                if not name['id'].startswith(SWITCH_PREFIX)
            ]

        return True

    @staticmethod
    def gather_vlan_interfaces(config):
        '''
        Collect information about tagged and untagged vlan interfaces in system
        from switches configuration.
        Returns two dictionaries (tagged and untagged) that map vlan ids
        to interface names.
        '''
        tagged = defaultdict(lambda: [])
        untagged = defaultdict(lambda: [])

        ports = [
            SwitchPort(port)
            for interface in config['interfaces']
            if interface['identification']['type'] == 'switch'
            and interface['switch']['vlanEnabled']
            for port in interface['switch']['ports']
        ]

        for port in ports:
            if port.pvid is not None:
                untagged[port.pvid].append(port.ifc_id)

            for vid in port.vlans:
                tagged[vid].append(port.ifc_id)

        return tagged, untagged

    def migrate(self, config):
        config['versionFormat'] = 'v2'
        config['versionDetail']['interfaces'] = 4

        if self.board_config['identification']['model-short'] != 'UDR':
            return

        if 'switches' in self.board_config:
            return

        tagged, untagged = self.gather_vlan_interfaces(config)

        # filter out unwanted interfaces
        config['interfaces'] = [
            interface for interface in config['interfaces']
            if self.check_interface(interface, tagged, untagged)
        ]

        config['interfaces'] += [{
            'addresses': [],
            'identification': {
                'id': '{}.{}'.format(ifc_id, vid),
                'type': 'vlan'
            },
            'status': {
                'enabled': True,
                'mtu': self.max_mtu,
                'speed': 'auto'
            },
            'vlan': {
                'id': vid,
                'interface': {
                    'id': ifc_id
                }
            }
        } for vid, interfaces in tagged.items()
          for ifc_id in interfaces]


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: {} <UDAPI config>'.format(sys.argv[0]))
        print('Migrates interfaces configuration from version 5 to version 4')
        sys.exit(1)

    udapi_config_path = sys.argv[1]
    config = json.load(open(udapi_config_path))

    board_config_path = get_board_config_path(udapi_config_path)
    board_config = json.load(open(board_config_path))

    migration = Migration(board_config)
    migration.migrate(config)

    json.dump(config, open(udapi_config_path,'w'), indent=1)
