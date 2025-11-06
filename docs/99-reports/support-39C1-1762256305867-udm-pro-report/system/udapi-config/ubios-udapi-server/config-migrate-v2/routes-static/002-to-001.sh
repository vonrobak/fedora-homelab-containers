#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# - bump version down
# - move all static route .nexthops[0] attributes to route body
# - remove unused .weight attribute
# - remove unused .scope attribute
JQA "${1}" '
    def downgrade_route(route):
        route | . * .nexthops[0]
              | del(.nexthops, .weight, .scope)
    ;

    .versionDetail."routes/static"=1
    |
    ."routes/static"[]? |= downgrade_route(.)
'

exit 0
