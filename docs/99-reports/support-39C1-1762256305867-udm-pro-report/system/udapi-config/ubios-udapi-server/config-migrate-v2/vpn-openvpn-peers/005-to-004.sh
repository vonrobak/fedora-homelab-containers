#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/openvpn/peers"=4'

# .encryptionCiphers[] degrades into .encryptionCipher
# but no reason to migrate it, .encryptionCipher is not working at all due to a bug
JQA "${1}" '(."vpn/openvpn/peers"[]?.tunnel? |= del(.encryptionCiphers))'

exit 0
