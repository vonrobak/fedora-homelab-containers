#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# Remove rule if geoip.negateCountryList == true.
# Remove geoip.negateCountryList property.
JQA "${1}" '.versionDetail."firewall/pbr"=7 |
    del(."firewall/pbr"?.rules[]? | select(.geoip?.negateCountryList? == true)) |
    del(."firewall/pbr"?.rules[]?.geoip?.negateCountryList?)'

exit 0
