#!/bin/sh
. "$(dirname "${0}")"/JQ # include JQ helper scripts
JQA "${1}" '.version=12'

# do nothing; We are not able to remove ipVersion field (that was added during 12->13) because
# we are not able to distinguish which was added automatically and which was intended.

exit 0
