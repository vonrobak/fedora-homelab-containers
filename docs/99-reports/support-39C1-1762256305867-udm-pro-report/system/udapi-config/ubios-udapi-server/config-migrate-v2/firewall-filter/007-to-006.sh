#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# Remove rule if geoip.negateCountryList == true.
# Remove geoip.negateCountryList property.
JQA "${1}" '.versionDetail."firewall/filter"=6 |
    del(."firewall/filter"[]?.rules[]? | select(.geoip?.negateCountryList? == true)) |
    del(."firewall/filter"[]?.rules[]?.geoip?.negateCountryList?)'

exit 0
