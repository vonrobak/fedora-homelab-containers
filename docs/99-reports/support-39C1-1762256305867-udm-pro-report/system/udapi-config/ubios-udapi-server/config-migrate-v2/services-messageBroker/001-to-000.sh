#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts
JQA "${1}" '
    def migrate_message_broker:
        .services.sslInspection.messageBroker += .services.messageBroker
        |
        .services.sslInspection.messageBroker.rabbitMq.user<FILTERED> = <FILTERED>
        |
        .services.sslInspection.messageBroker.rabbitMq.password = <FILTERED>
        |
        del(.services.sslInspection.messageBroker.enabled)
        |
        del(.services.sslInspection.messageBroker.rabbitMq.authentication);

    if .services.sslInspection then (migrate_message_broker) else . end
    |
    del(.versionDetail."services/messageBroker")
    |
    del(.services.messageBroker)
'

exit 0
