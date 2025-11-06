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

    @property
    def enabled(self):
        return self.pvid is not None or self.vlans != []

    def make_switch_entry(self, ifc_id):
        return {
            'interface': {
                'id': ifc_id
            },
            'pvid': self.pvid,
            'vid': sorted(self.vlans),
            'enabled': self.enabled
        }


class Migration:
    '''
    Migrate standalone-ports-based to switch0-based interface config.
    '''
    def __init__(self, board_config):
        self.board_config = board_config
        self.switches = {}
        self.default_switch = None
        self.switch_ports = defaultdict(lambda: defaultdict(lambda: VlanConfig()))
        self.vid_by_bridge = {}
        self.all_switch_vlans = set()
        #self.all_bridge_members = set()
        self.switch_by_port = {}
        self.max_mtu = 1500

    def update_mtu(self, mtu):
        if mtu is None:
            return

        if mtu > self.max_mtu:
            self.max_mtu = mtu

    def get_switch_by_port(self, ifc_id):
        if ifc_id.startswith('lag'):
            return self.default_switch

        return self.switch_by_port.get(ifc_id)

    def gather_settings(self, config):
        self.switches = {
            switch['id']: [ port['interface']['id'] for port in switch['edge-ports']]
            for switch in self.board_config['switches']
        }

        self.default_switch = min(self.switches.key<FILTERED>())

        for switch, ports in self.switches.items():
            for port in ports:
                self.switch_by_port[port] = switch
                self.switch_ports[switch][port] = VlanConfig()

        for interface in config['interfaces']:
            self.visit_interface(interface)

    def visit_bridge_port(self, brport_name, bridge_vid):
        '''
        Collects information about tagged and untagged vlans
        from the list of bridge ports for the given bridge and its vid.
        '''
        #self.all_bridge_members.add(brport_name)
        base_ifc_id, vid = path.splitext(brport_name)

        switch_id = self.get_switch_by_port(base_ifc_id)
        if switch_id is None:
            return
        ports = self.switch_ports[switch_id]

        if vid:
            ports[base_ifc_id].add_tagged_vlan(bridge_vid)
        else:
            ports[base_ifc_id].set_pvid(bridge_vid)

    def visit_interface(self, interface):
        '''
        Collects vlan and bridge settings.
        '''
        identification = interface['identification']
        ifc_id = identification['id']

        if identification['type'] == 'bridge' and ifc_id.startswith(BRIDGE_PREFIX):
            bridge_vid = int(ifc_id[len(BRIDGE_PREFIX):])
            # br0 stands for vlan 1
            if bridge_vid == 0:
                bridge_vid = 1

            self.all_switch_vlans.add(bridge_vid)
            self.vid_by_bridge[ifc_id] = bridge_vid
            for member in interface['bridge']['interfaces']:
                self.visit_bridge_port(member['id'], bridge_vid)

    def transmute_bridge_members(self, members, vid):
        '''
        Replaces bridge members that are switch ports or their vlan derivatives
        with corresponding switchX.V interfaces without affecting general order.
        That is, if some non-switch interface was first or last in the list -
        it will keep its relative position after transmutation.
        '''
        result = []

        switches_added = {switch: False for switch in self.switches}
        for member in members:
            base_ifc_id, _ = path.splitext(member['id'])
            switch_id = self.get_switch_by_port(base_ifc_id)
            if switch_id is not None:
                if not switches_added[switch_id]:
                    result.append({'id': '{}.{}'.format(switch_id, vid)})
                    switches_added[switch_id] = True
            else:
                result.append(member)

        return result

    def filter_interface(self, interface):
        '''
        Return value indicates whether given interface should be
        kept in interface list (True) or removed from it (False).
        Using this function as a filter on interface list results
        in removal of entries for vlan-interfaces based on switch ports,
        excluding those that are deemed standalone - i.e. are not
        themselves a member of any bridge.
        Modifies contents of bridge interfaces: removes physical ports
        and their vlan interfaces, puts `switch0.X` into bridges instead.
        Also handles max MTU gathering.
        '''
        identification = interface['identification']
        ifc_id = identification['id']

        if identification['type'] == 'switch':
            # remove existing switch entries
            return False

        bridge_vid = self.vid_by_bridge.get(ifc_id, None)
        if bridge_vid is not None:
            interface['bridge']['interfaces'] = self.transmute_bridge_members(
                interface['bridge']['interfaces'], bridge_vid
            )
            self.update_mtu(interface.get('status',{}).get('mtu', None))
            return True

        if identification['type'] == 'vlan':
            base_ifc_id = interface['vlan']['interface']['id']

            vid = int(interface['vlan']['id'])
            switch_id = self.get_switch_by_port(base_ifc_id)

            if switch_id is None:
                return True

            vlan_entry = self.switch_ports[switch_id][base_ifc_id]
            if vlan_entry.enabled:
                self.update_mtu(interface.get('status',{}).get('mtu', None))

            return not vlan_entry.enabled

        return True

    @staticmethod
    def has_switch_setup(interfaces):
        def ok_switch(interface):
            return (
                'identification' in interface
                and interface['identification']['type'] == 'switch'
                and 'switch' in interface
                and interface['switch']['vlanEnabled']
            )

        return any(ok_switch(interface) for interface in interfaces)

    def migrate(self, config):
        config['versionFormat'] = 'v2'
        config['versionDetail']['interfaces'] = 31

        board_id = self.board_config['identification']['board-id']
        early_exit = (
            (board_id != 'ea3d' and board_id != 'ea3e') # allow only EFG and UXGEnt
            or 'switches' not in self.board_config
            or self.has_switch_setup(config['interfaces'])
        )
        if early_exit:
            return

        self.gather_settings(config)

        # filter out interfaces that should disappear
        config['interfaces'] = [
            interface for interface in config['interfaces']
            if self.filter_interface(interface)
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
                    vlan_entry.make_switch_entry(ifc_id)
                    for _, ports in self.switch_ports.items()
                    for ifc_id, vlan_entry in ports.items()
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
        } for vid in sorted(list(self.all_switch_vlans))
          for switch in self.switches]


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: {} <UDAPI config> [Migrated config] [Board config]'.format(sys.argv[0]))
        print('Migrates interfaces configuration from version 30 to version 31')
        sys.exit(1)

    udapi_config_path = sys.argv[1]
    migrated_config_path = sys.argv[2] if len(sys.argv) > 2 else udapi_config_path
    config = json.load(open(udapi_config_path))

    board_config_path = sys.argv[3] if len(sys.argv) > 3 else get_board_config_path(udapi_config_path)
    board_config = json.load(open(board_config_path))

    migration = Migration(board_config)
    migration.migrate(config)

    json.dump(config, open(migrated_config_path,'w'), indent=1)
