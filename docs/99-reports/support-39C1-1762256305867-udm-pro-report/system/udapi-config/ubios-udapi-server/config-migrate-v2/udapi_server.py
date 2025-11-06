from os import path
from glob import iglob

__all__ = [
    'UBNTHAL_SYSTEM_INFO',
    'BRIDGE_PREFIX',
    'SWITCH_PREFIX',
    'read_ubnt_config',
    'get_board_config_path'
]

UBNTHAL_SYSTEM_INFO='/proc/ubnthal/system.info'

BRIDGE_PREFIX = 'br'
SWITCH_PREFIX = 'switch'

def read_ubnt_config(path):
    '''
    Returns dictionary of all entries in given ubnt config.
    '''
    lines = open(path).read().splitlines()
    return dict(tuple(line.split('=')) for line in lines)

def get_board_config_path(udapi_config_path):
    '''
    First, check if we're running on a console with `ubnthal`.
    Otherwise, look for the board-config in the same folder as our input config.
    It should have the same name as input config with 'board-' prefix, with or without '.<feature>_<version>_to_version>' suffix.
    This is meant to be a way to test this functionality without ubnthal or board-config file in known location.
    '''
    if path.exists(UBNTHAL_SYSTEM_INFO):
        system_info = read_ubnt_config(UBNTHAL_SYSTEM_INFO)
        board_config_glob = '/usr/share/ubios-udapi-server/config-board/*-{}.json'.format(system_info['systemid'])
        for board_config_path in iglob(board_config_glob):
            return board_config_path

    name = 'board-' + path.basename(udapi_config_path)
    test_board_config_path = path.join(path.dirname(udapi_config_path), name)
    if path.exists(test_board_config_path):
        return test_board_config_path
    
    test_board_config_path, _ = path.splitext(test_board_config_path)
    if path.exists(test_board_config_path):
        return test_board_config_path    

    raise FileNotFoundError('Matching board config not found')
