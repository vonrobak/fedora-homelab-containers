#!/usr/bin/env python3

import sys
import json
from os import path

sys.path.append(path.join(path.dirname(__file__),'..'))
from udapi_server import get_board_config_path, BRIDGE_PREFIX

class LagConfig:
    def __init__(self, lag_iface_entry):
        self.lag_iface_entry = lag_iface_entry
        self.lag = lag_iface_entry.get('lag',{})

    @property
    def ifc_id(self):
        return self.lag_iface_entry['identification']['id']

    @property
    def has_addresses(self):
        return bool(self.lag_iface_entry.get('addresses', []))

    @property
    def ports(self):
        return [p['id'] for p in self.lag.get('interfaces', []) if 'id' in p]


class SwitchConfig:
    def __init__(self, switch_iface_entry):
        self.switch_iface_entry = switch_iface_entry
        self.switch_entry = switch_iface_entry['switch']
        self.ports = self.switch_entry['ports']

    def get_ports(self):
        return self.switch_entry['ports']
    def set_ports(self, ports):
        self.switch_entry['ports'] = ports
    ports = property(get_ports, set_ports)

    @property
    def mtu(self):
        return self.switch_iface_entry.get('status',{}).get('mtu', 1500)


class SwitchportConfig:
    def __init__(self, port_entry, switch_config):
        self.switch_config = switch_config
        self.port_entry = port_entry

        if 'vid' not in port_entry:
            port_entry['vid'] = []

    @property
    def ifc_id(self):
        return self.port_entry['interface']['id']

    @classmethod
    def create(cls, ifc_id, enabled=False):
        return cls({
            'interface': {
                'id': ifc_id
            },
            'pvid': None,
            'vid': [],
            'enabled': enabled,
        }, None)

    def get_vid(self):
        return self.port_entry['vid']
    def set_vid(self, vid):
        self.port_entry['vid'] = vid
    vid = property(get_vid, set_vid)

    def get_pvid(self):
        return self.port_entry.get('pvid')
    def set_pvid(self, pvid):
        self.port_entry['pvid'] = pvid
    pvid = property(get_pvid, set_pvid)

    def get_enabled(self):
        return self.port_entry.get('enabled', False)
    def set_enabled(self, value):
        if value:
            self.port_entry['enabled'] = True
        else:
            self.port_entry['enabled'] = False
            self.port_entry['pvid'] = None
            self.port_entry['vid'] = []
    enabled = property(get_enabled, set_enabled)


class VlanConfig:
    def __init__(self, iface_entry):
        self.iface_entry = iface_entry
        self.vlan = iface_entry.get('vlan', {})

    @property
    def ifc_id(self):
        return self.iface_entry['identification']['id']

    @property
    def parent(self):
        return self.vlan.get('interface', {}).get('id')

    @property
    def vid(self):
        return self.vlan.get('id')

    @property
    def has_addresses(self):
        return bool(self.lag_iface_entry.get('addresses', []))

    @classmethod
    def create(cls, parent, vlan_id, mtu):
        return cls({
            'addresses': [],
            'identification': {
                'id': f'{parent}.{vlan_id}',
                'type': 'vlan'
            },
            'status': {
                'arpProxy': False,
                'enabled': True,
                'mtu': mtu,
                'speed': 'auto'
            },
            'vlan': {
                'egressQoSMap': [],
                'id': vlan_id,
                'ingressQoSMap': [],
                'interface': {
                    'id': parent
                }
            }
        })


class Conflict:
    def __init__(self, ports, lag_switchport_cfg, common_switch_config, lag_config):
        self.ports = ports # port ifc id -> SwitchportConfig
        self.lag = lag_switchport_cfg
        self.common_switch_config = common_switch_config
        self.lag_config = lag_config

        self.common_pvid = set.intersection(*[{p.pvid} for p in self.ports.values()])
        self.common_vids = set.intersection(*[set(p.vid) for p in self.ports.values()])
        self.unique_pvids = {
            ifc_id: {port_cfg.pvid}.difference(self.common_pvid)
            for ifc_id, port_cfg in self.ports.items()
        }
        self.unique_vids = {
            ifc_id: set(port_cfg.vid).difference(self.common_vids)
            for ifc_id, port_cfg in self.ports.items()
        }


class Setup:
    def __init__(self, config):
        self.interfaces = config.get('interfaces', [])
        self.vlans = {} # parent ifc id -> vlan config
        self.lags = {} # ifc_id -> lag config
        self.switches = {} # ifc_id -> switch iface
        self.bridges = {} # vlan -> bridge entry
        self.switch_ports = {} # port ifc id -> SwitchportConfig
        self.gather(config)

        self.conflicts = []
        for lag_ifc_id, lag_config in self.lags.items():
            lag_port_cfgs = {p:self.switch_ports.get(p) for p in lag_config.ports}
            switches = {cfg.switch_config for cfg in lag_port_cfgs.values() if cfg is not None}

            if len(switches) == 0 or all(bool(cfg.enabled) is False for cfg in lag_port_cfgs.values()):
                # there are no enabled switchports for members of this lag - no conflict
                continue
            elif len(switches) > 1:
                print('LAG members are mentioned as switchports in multiple switches')

            common_switch_config = next(iter(switches))
            self.conflicts.append(Conflict(
                {p:self.switchport_find_or_create(p, common_switch_config) for p in lag_config.ports},
                self.switchport_find_or_create(lag_ifc_id, common_switch_config),
                common_switch_config,
                lag_config
            ))

    def switchport_find_or_create(self, ifc_id, common_switch_config):
        if ifc_id in self.switch_ports:
            cfg = self.switch_ports[ifc_id]
            if cfg.switch_config is not common_switch_config:
                print(f'Switchport[{ifc_id}] exists in a different switch than its ports')
            return cfg

        return SwitchportConfig.create(ifc_id, enabled=False)

    def gather(self, config):
        for iface in self.interfaces:
            identification = iface['identification']
            ifc_id = identification['id']
            t = identification['type']

            if t == 'bridge':
                bridge = iface['bridge']
                bridge_vid = bridge.get('id')
                if bridge_vid is None:
                    print(f'Bridge[{ifc_id}] has no id set')
                    continue
                # id 0 stands for vlan 1
                if bridge_vid == 0:
                    bridge_vid = 1
                self.bridges[bridge_vid] = bridge
            elif t == 'switch':
                switch_config = SwitchConfig(iface)
                for port_entry in switch_config.ports:
                    port_config = SwitchportConfig(port_entry, switch_config)
                    self.switch_ports[port_config.ifc_id] = port_config
            elif t == 'lag':
                self.lags[ifc_id] = LagConfig(iface)
            elif t == 'vlan':
                vlan_config = VlanConfig(iface)
                if vlan_config.parent in self.vlans:
                    self.vlans[vlan_config.parent].append(vlan_config)
                else:
                    self.vlans[vlan_config.parent] = [vlan_config]



class Migration:
    '''
    Fix lag-related compatibility issues.
    '''
    def __init__(self, board_config):
        self.board_config = board_config

    def reify_switchport(self, ifc_id, vid, mtu, setup, lag_name):
        vlan_cfg = VlanConfig.create(ifc_id, vid, mtu)
        setup.interfaces.append(vlan_cfg.iface_entry)

        setup.bridges[vid]['interfaces'].append({
            'id': vlan_cfg.ifc_id
        })
        print(f'Unique tagged vlan interface for vid[{vid}] created for port[{ifc_id}](lag[{lag_name}])')

    def resolve_switch_restricted_lag(self, setup, conflict):
        if conflict.lag.enabled:
            return False

        descendants = setup.vlans.get(conflict.lag_config.ifc_id, [])
        vids = set(d.vid for d in descendants)

        if not conflict.lag_config.has_addresses and not vids:
            return False

        for ifc_id, port_cfg in conflict.ports.items():
            if port_cfg.pvid is not None:
                print(f'Ignoring non-null pvid[{port_cfg.pvid}] on port[{ifc_id}] for lag[{conflict.lag.ifc_id}]')

            for vid in port_cfg.vid:
                if vid in vids:
                    print(f'Ignoring vid[{vid}] on port[{ifc_id}] for lag[{conflict.lag.ifc_id}] due to existence of lag vlan interface for this vid')
                else:
                    self.reify_switchport(ifc_id, vid, conflict.common_switch_config.mtu, setup, conflict.lag.ifc_id)

            port_cfg.enabled = False

        return True


    def resolve(self, setup, conflict):
        lag = conflict.lag

        if self.resolve_switch_restricted_lag(setup, conflict):
            return

        if conflict.common_pvid:
            # there is a common pvid shared by all conflict ports
            pvid = next(iter(conflict.common_pvid))
            if pvid is not None:
                if lag.pvid is None:
                    # there is a vacant pvid place in LAG switchport entry
                    lag.pvid = pvid
                else:
                    print(f'There is a common pvid[{pvid}] among conflict switchports on [{lag.ifc_id}] but it already has pvid[{lag.pvid}]')
        else:
            # select first available unique pvid as LAG pvid
            for ifc_id, pvid_set in conflict.unique_pvids.items():
                if pvid_set:
                    pvid = next(iter(pvid_set))
                    if pvid is not None:
                        if lag.pvid is None:
                            print(f'Unique pvid[{pvid}] from port[{ifc_id}] selected as pvid for lag[{lag.ifc_id}]')
                            lag.pvid = pvid
                            break
                        else:
                            print(f'Unique pvid[{pvid}] exists on port[{ifc_id}] but lag[{lag.ifc_id}] already has pvid[{lag.pvid}]')

        lag_vid_set = set(conflict.lag.vid).union(conflict.common_vids).difference({lag.pvid})
        lag.vid = sorted(lag_vid_set)

        if not lag.enabled and (lag.pvid is not None or lag.vid):
            # conflict resolution activated previously dormant LAG switchport entry
            lag.enabled = True

        if lag.enabled and lag.switch_config is None:
            # create previously absent switchport entry for LAG
            conflict.common_switch_config.ports.append(lag.port_entry)
            lag.switch_config = conflict.common_switch_config

        for ifc_id, unique_vids in conflict.unique_vids.items():
            # create unique tagged vlan interfaces as separate entities and add them to matching bridges
            for vid in unique_vids:
                if vid == lag.pvid:
                    print(f'Unique tagged vlan[{vid}] for port[{ifc_id}] is superseded by its lag[{lag.ifc_id}] pvid vlan')
                    continue

                if vid in lag_vid_set:
                    print(f'Unique tagged vlan[{vid}] for port[{ifc_id}] is superseded by its lag[{lag.ifc_id}] tagged vlan')
                    continue

                if vid not in setup.bridges:
                    print(f'Bridge for vlan[{vid}] (necessary for unique tagged vid on port[{ifc_id}]) does not exist')
                    continue

                self.reify_switchport(ifc_id, vid, conflict.common_switch_config.mtu, setup, lag.ifc_id)

        # disable conflict switchports
        for port_cfg in conflict.ports.values():
            port_cfg.enabled = False


    def migrate(self, config):
        config['versionFormat'] = 'v2'
        config['versionDetail']['interfaces'] = 32

        if self.board_config is None:
            return

        board_id = self.board_config['identification']['board-id']
        early_exit = (
            (board_id != 'ea3d' and board_id != 'ea3e') # allow only EFG and UXGEnt
            or 'switches' not in self.board_config
        )
        if early_exit:
            return

        setup = Setup(config)
        for conflict in setup.conflicts:
            self.resolve(setup, conflict)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: {} <UDAPI config> [Migrated config] [Board config]'.format(sys.argv[0]))
        print('Migrates interfaces configuration from version 31 to version 32')
        sys.exit(1)

    udapi_config_path = sys.argv[1]
    migrated_config_path = sys.argv[2] if len(sys.argv) > 2 else udapi_config_path
    config = json.load(open(udapi_config_path))

    try:
        board_config_path = sys.argv[3] if len(sys.argv) > 3 else get_board_config_path(udapi_config_path)
        board_config = json.load(open(board_config_path))
    except FileNotFoundError:
        print('Board config not found')
        board_config = None
    except json.decoder.JSONDecodeError as e:
        print(f'Bad board config json: {e}')
        board_config = None

    migration = Migration(board_config)
    migration.migrate(config)

    json.dump(config, open(migrated_config_path,'w'), indent=1)
