#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/wifiman"=2'

WIFIMAN_SERVER_DIR="/data/wifiman-server"

if [ -d "$WIFIMAN_SERVER_DIR" ]; then
	rm -Rf $WIFIMAN_SERVER_DIR
fi

exit 0
