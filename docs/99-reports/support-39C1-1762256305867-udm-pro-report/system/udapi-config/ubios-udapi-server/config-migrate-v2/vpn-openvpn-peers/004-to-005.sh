#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."vpn/openvpn/peers"=5'

# .encryptionCipher changes to .encryptionCiphers[]
# but it should not be present, .encryptionCipher was not working at all due to a bug
JQA "${1}" '(."vpn/openvpn/peers"[]?.tunnel? |= del(.encryptionCipher))'

exit 0
