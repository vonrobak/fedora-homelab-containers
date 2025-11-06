#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/wanFailover"=2'

# no need to upgrade from 001 to 002 in cases:
# - if no wanFailover service, then nothing to update
JQT "${1}" '.services.wanFailover' || exit 0
# - if no interfaces are present, then nothing to update
JQT "${1}" '.services.wanFailover.wanInterfaces[]?' || exit 0
# - if failoverGroups are present, then format is already updated
JQT "${1}" '.services.wanFailover.failoverGroups' && exit 0
# - if interfaces are present and no interfaceIdentification is used, then format is already updated
JQT "${1}" '.services.wanFailover.wanInterfaces[]?.interface?.id?' || exit 0

# convert InterfaceIdentification to InterfaceID
JQA "${1}" '
    (. | select(has("services")) | .services | select(has("wanFailover")) | .wanFailover) |= (
        (.wanInterfaces[]?) |= (.interface=.interface.id)
    )
'

# add ex-default 'icmp' type for all monitors
JQA "${1}" '
    (. | select(has("services")) | .services | select(has("wanFailover")) | .wanFailover) |= (
        (.wanInterfaces[]?.monitors[]? | select(has("type") | not)) |= (.type="icmp")
    )
'

# for each interface create a group of type 'single' and assign an id to it
JQA "${1}" '
    def make_group($wan):
       del(.) | (.id=null)
              | (.algorithm="single")
              | (.interfaces=[$wan.interface])
              | (.metric=$wan.metric);

    (. | select(has("services")) | .services | select(has("wanFailover")) | .wanFailover) |= (
        .failoverGroups = .wanInterfaces |
        .failoverGroups[]? |= make_group(.) |
        .failoverGroups |= to_entries |
        .failoverGroups[]? |= (.value.id=.key<FILTERED>) |
        .failoverGroups[]? |= .value
    )
'

exit 0
