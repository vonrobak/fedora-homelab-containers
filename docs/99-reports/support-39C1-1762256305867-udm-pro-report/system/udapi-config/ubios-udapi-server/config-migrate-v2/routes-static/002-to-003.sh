#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# - translate .type from .nexthops[0] to route .type
# - remove .type from .nexthops[0]

JQA "${1}" '
  def transform_route(route):
    route
    | if any(.nexthops[]?; .type == "blackhole") then
        .type = "blackhole"
        | .nexthops = [.nexthops[0] | del(.type, .interface, .gateway)]
      else
        .type = "unicast"
        | del(.nexthops[]?.type)
      end;

  .versionDetail."routes/static"=3
  |
  ."routes/static"[]? |= transform_route(.)
'

exit 0
