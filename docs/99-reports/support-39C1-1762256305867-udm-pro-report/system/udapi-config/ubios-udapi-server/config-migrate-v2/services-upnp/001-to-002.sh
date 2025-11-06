#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/upnp"=2 | .versionFormat="v2"'

# remove invalid upnp ports
JQA "${1}" '
    del(.services.upnp.acl[]?.externalPort | select ( . // "" | split("-")[]? | tonumber | . > 65535 or . < 0))
    |
    del(.services.upnp.acl[]?.localPort | select ( . // "" | split("-")[]? | tonumber | . > 65535 or . < 0))'

exit 0
