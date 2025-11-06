#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=23'

# remove .translation from all NAT rules where target is neither SNAT nor DNAT

JQA "${1}" '(."firewall/nat"[]? | select(has("target") and has("translation")))
                |= (if .target | contains("SNAT") or contains("DNAT")
                        then .
                        else del(.translation)
                    end)'

exit 0
