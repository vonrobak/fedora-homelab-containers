#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '.versionDetail."services/vrrp"=1 | .versionFormat="v2"'

# It is not possible to correctly migrate VRRP configuration because VRRP
# interface have been split into:
#  * vrrp.instances[].interface              - handles management traffic
#  * vrrp.instances[].virtualIp[].interface  - handles data traffic
# 
# Here we simply delete the VRRP configuration because upgrade script does not
# know where customer is expecting VRRP management taffic and where he want to 
# see data traffic.
#
# Such approach will not cause any troubles because VRRP has not been used prror 
# to "versionDetail.services/vrrp=2"; it only ensures that older `udapi-server`
# would not reject newer VRRP configuration.
JQA "${1}" 'del(.services?.vrrp?)'

exit 0
