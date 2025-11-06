#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

# - translate static route's .type into .nexthops[0]
# - remove static route's .type

JQA "${1}" '
  def transform_route(route):
    (route.type as $type
    | route
    | .nexthops = (
      .nexthops
      | map(
          if $type == "blackhole" then
            . + {type: "blackhole"}
          elif has("gateway") then
            . + {type: "gateway"}
          elif has("interface") then
            . + {type: "interface"}
          else
            .
          end
        )
      )
    | del(.type)
    )
  ;

  .versionDetail."routes/static"=2
  |
  ."routes/static" |=
    map(
      select(
        .type != "local" and
        .type != "unspecified" and
        (
          .type != "unicast" or
          ((.nexthops // []) | map(has("gateway") or has("interface")) | any)
        )
      )
      | transform_route(.)
    )
'

exit 0
