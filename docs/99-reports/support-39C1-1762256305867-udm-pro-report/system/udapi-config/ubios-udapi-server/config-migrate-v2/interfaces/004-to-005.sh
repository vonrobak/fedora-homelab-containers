#!/usr/bin/env python3

import sys
import json
from os import path
from collections import defaultdict

sys.path.append(path.join(path.dirname(__file__),'..'))
from udapi_server import get_board_config_path, BRIDGE_PREFIX


class VlanConfig:
    def __init__(self):
        self.pvid = None
        self.vlans = []

    def add_tagged_vlan(self, vid):
        self.vlans.append(vid)

    def set_pvid(self, pvid):
        self.pvid = pvid

    def make_switch_entry(self, ifc_id):
        return {
            'interface': {
                'id': ifc_id
            },
            'pvid': self.pvid,
            'vid': self.vlans,
            'enabled': self.pvid is not None or self.vlans != []
        }


class Migration:
    '''
    Migrate standalone-ports-based to switch0-based interface config.
    '''
    def __init__(self, board_config):
        self.board_config = board_config
        self.switches = {}
        self.ports = defaultdict(lambda: VlanConfig())
        self.all_vlans = []
        self.max_mtu = 1500

    def among_switch_ports(self, port):
        for switch, ports in self.switches.items():
            if port in ports:
                return True

        return False

    def check_bridge_port(self, brport_name, bridge_vid):
        '''
        Filter for bridge port member list.
        Collects information about tagged and untagged vlans
        from the list of bridge ports for the given bridge and its vid.
        Return value indicates whether given interface should be kept
        among bridge ports (True) or removed (False).
        Using this function as a filter results in removal of bridge port 
        entries for physical ports and their vlan derivatives.
        '''
        brport_base, vid = path.splitext(brport_name)
        if not self.among_switch_ports(brport_base):
            return True

        if vid:
            self.ports[brport_base].add_tagged_vlan(bridge_vid)
        else:
            self.ports[brport_base].set_pvid(bridge_vid)

        return False

    def check_interface(self, interface):
        '''
        Filter for interface list.
        Collects information about vlans configured in system.
        Modifies contents of bridge interfaces: remove physical ports
        and their vlan interfaces, put `switch0.X` into bridges instead.
        Return value indicates whether given interface should be
        kept in interface list (True) or removed from it (False).
        Using this function as a filter on interface list results
        in removal of entries for physical ports and their vlan derivatives.
        '''
        identification = interface['identification']
        ifc_id = identification['id']

        if self.among_switch_ports(ifc_id):
            mtu = interface.get('status',{}).get('mtu', None)
            if mtu is not None and mtu > self.max_mtu:
                self.max_mtu = mtu

        if identification['type'] == 'vlan':
            base_ifc_id = interface['vlan']['interface']['id']
            return not self.among_switch_ports(base_ifc_id)

        if identification['type'] == 'bridge' and ifc_id.startswith(BRIDGE_PREFIX):
            bridge_vid = int(ifc_id[len(BRIDGE_PREFIX):])
            # br0 stands for vlan 1
            if bridge_vid == 0:
                bridge_vid = 1

            interface['bridge']['interfaces'] = [
                entry for entry
                in interface['bridge']['interfaces']
                if self.check_bridge_port(entry['id'], bridge_vid)
            ] + [
                {'id': '{}.{}'.format(switch, bridge_vid)}
                for switch in self.switches
            ]

            self.all_vlans.append(bridge_vid)

        return True

    @staticmethod
    def has_switch_setup(interfaces):
        return any(interface['identification']['type'] == 'switch'
                   for interface in interfaces)

    def migrate(self, config):
        config['versionFormat'] = 'v2'
        config['versionDetail']['interfaces'] = 5

        if self.board_config['identification']['model-short'] != 'UDR':
            return

        if 'switches' not in self.board_config:
            return

        if self.has_switch_setup(config['interfaces']):
            # special case to avoid processing configuration
            # already containing switch-based setup
            return

        # maps switch name to the list of its edge ports
        self.switches = {
            switch['id']: [port['interface']['id'] for port in switch['edge-ports']]
            for switch in board_config['switches']
        }

        # gather vlan setup, filter out unwanted interfaces and bridge ports
        config['interfaces'] = [
            interface for interface in config['interfaces']
            if self.check_interface(interface)
        ]

        config['interfaces'] += [{
            'addresses': [],
            'identification': {
                'id': switch,
                'type': 'switch'
            },
            'status': {
                'enabled': True,
                'mtu': self.max_mtu,
                'speed': 'auto'
            },
            'switch': {
                'vlanEnabled': True,
                'ports': [
                    self.ports[ifc_id].make_switch_entry(ifc_id)
                    for ifc_id in switch_ports
                ]
            }
        } for switch, switch_ports in self.switches.items()]

        config['interfaces'] += [{
            'addresses': [],
            'identification': {
                'id': '{}.{}'.format(switch, vid),
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
                    'id': switch
                }
            }
        } for vid in self.all_vlans
          for switch in self.switches]


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: {} <UDAPI config>'.format(sys.argv[0]))
        print('Migrates interfaces configuration from version 4 to version 5')
        sys.exit(1)

    udapi_config_path = sys.argv[1]
    config = json.load(open(udapi_config_path))

    board_config_path = get_board_config_path(udapi_config_path)
    board_config = json.load(open(board_config_path))

    migration = Migration(board_config)
    migration.migrate(config)

    json.dump(config, open(udapi_config_path,'w'), indent=1)
