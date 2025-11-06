#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# - bump version up
# - move each static route's .type, .gateway and .interface into .nexthops[0]
JQA "${1}" '
    def copy_attribute(attribute; attribute_name):
        if attribute != null then { (attribute_name): attribute } else {} end
    ;

    def make_nexthop(route):
        {} + copy_attribute(route.type; "type")
           + copy_attribute(route.gateway; "gateway")
           + copy_attribute(route.interface; "interface")
    ;

    def upgrade_route(route):
        route | .nexthops=[make_nexthop(route)]
              | del(.type, .gateway, .interface)
    ;

    .versionDetail."routes/static"=2
    |
    ."routes/static"[]? |= upgrade_route(.)
'

exit 0
