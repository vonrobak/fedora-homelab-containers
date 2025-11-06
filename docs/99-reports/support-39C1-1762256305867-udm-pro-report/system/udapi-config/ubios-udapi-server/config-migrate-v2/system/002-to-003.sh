#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."system"=3'

# gc_thresh1 = 32768
# gc_thresh2 = 131072
# gc_thresh3 = 262144
# It makes gc_thresh1 as 32,768, so it avoids GC entirely for more than the expected max number of entries
JQA "${1}" '.system.arp.arpCacheSize=262144'

exit 0
