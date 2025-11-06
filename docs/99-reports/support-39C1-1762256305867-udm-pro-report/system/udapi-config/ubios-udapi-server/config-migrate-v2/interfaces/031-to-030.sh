#!/usr/bin/env python3

import sys
import json
from os import path
from collections import defaultdict
from functools import reduce

sys.path.append(path.join(path.dirname(__file__),'..'))
from udapi_server import get_board_config_path, BRIDGE_PREFIX, SWITCH_PREFIX

def partition(iterable, predicate):
    '''
    Split contents of a given iterable into two lists:
    ([true predicate entries],[false predicate entries])
    '''
    return reduce(lambda ret, entry: ret[not predicate(entry)].append(entry) or ret, iterable, ([], []))

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

    @classmethod
    def is_bridge(cls, interface):
        identification = interface['identification']
        return cls.is_bridge_by_id(identification)

    @staticmethod
    def is_bridge_by_id(identification):
        ifc_id = identification['id']
        t = identification['type']
        return t == 'bridge' and ifc_id.startswith(BRIDGE_PREFIX)

    def transmute_bridge_members(self, members, bridge_vid, tagged, untagged):
        '''
        Replaces switch-derived bridge members with their standalone equivalents
        according to tagged and untagged configuration.
        If first member is not a switch-derived interface then it will keep its position.
        '''
        non_switch_members = [
            member for member in members
            if not member['id'].startswith(SWITCH_PREFIX)
        ]
        if len(non_switch_members) == len(members):
            return members

        switch_members = [
            {'id': ifc_id} for ifc_id in untagged[bridge_vid]
        ] + [
            {'id':f'{ifc_id}.{bridge_vid}'} for ifc_id in tagged[bridge_vid]
        ]

        if len(non_switch_members) > 0 and members[0] == non_switch_members[0]:
            return non_switch_members + switch_members
        else:
            return switch_members + non_switch_members

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

        if self.is_bridge_by_id(identification):
            bridge_vid = int(ifc_id[len(BRIDGE_PREFIX):])
            # br0 stands for vlan 1
            if bridge_vid == 0:
                bridge_vid = 1

            interface['bridge']['interfaces'] = self.transmute_bridge_members(
                interface['bridge']['interfaces'], bridge_vid, tagged, untagged
            )

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
        config['versionDetail']['interfaces'] = 30

        board_id = self.board_config['identification']['board-id']
        early_exit = (
            (board_id != 'ea3d' and board_id != 'ea3e') # allow only EFG and UXGEnt
            or 'switches' in self.board_config
        )
        if early_exit:
            return

        tagged, untagged = self.gather_vlan_interfaces(config)

        bridges, rest = partition([
            interface for interface in config['interfaces']
            if self.check_interface(interface, tagged, untagged)
        ], self.is_bridge)

        vlans_to_create = [(ifc_id, vid) for vid, interfaces in tagged.items() for ifc_id in interfaces]
        vlans_to_create.sort()

        config['interfaces'] = rest + [{
            'addresses': [],
            'identification': {
                'id': '{}.{}'.format(ifc_id, vid),
                'type': 'vlan'
            },
            'status': {
                'arpProxy': False,
                'enabled': True,
                'mtu': self.max_mtu,
                'speed': 'auto'
            },
            'vlan': {
                "egressQoSMap": [],
                'id': vid,
                "ingressQoSMap": [],
                'interface': {
                    'id': ifc_id
                }
            }
        } for ifc_id, vid in vlans_to_create] + bridges

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: {} <UDAPI config> [Migrated config] [Board config]'.format(sys.argv[0]))
        print('Migrates interfaces configuration from version 31 to version 30')
        sys.exit(1)

    udapi_config_path = sys.argv[1]
    migrated_config_path = sys.argv[2] if len(sys.argv) > 2 else udapi_config_path
    config = json.load(open(udapi_config_path))

    board_config_path = sys.argv[3] if len(sys.argv) > 3 else get_board_config_path(udapi_config_path)
    board_config = json.load(open(board_config_path))

    migration = Migration(board_config)
    migration.migrate(config)

    json.dump(config, open(migrated_config_path,'w'), indent=1)
