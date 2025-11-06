#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# Remove rule if geoip.negateCountryList == true.
# Remove geoip.negateCountryList property.
JQA "${1}" '.versionDetail."firewall/mangle"=7 |
    del(."firewall/mangle"[]?.rules[]? | select(.geoip?.negateCountryList? == true)) |
    del(."firewall/mangle"[]?.rules[]?.geoip?.negateCountryList?)'

exit 0
