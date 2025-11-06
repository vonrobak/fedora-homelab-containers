#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/wifiman"=1'

WIFIMAN_SERVER_DIR="/data/wifiman"

if [ -d "$WIFIMAN_SERVER_DIR" ]; then
	rm -Rf $WIFIMAN_SERVER_DIR
fi

exit 0
