#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

JQA "${1}" '
    def migrate_message_broker:
        .services.messageBroker += .services.sslInspection.messageBroker
        |
        .services.messageBroker.enabled=false
        |
        .services.messageBroker.rabbitMq.authentication.user<FILTERED> = <FILTERED>
        |
        .services.messageBroker.rabbitMq.authentication.password = <FILTERED>
        |
        del(.services.messageBroker.rabbitMq.user<FILTERED>)
        |
        del(.services.messageBroker.rabbitMq.password)
        |
        del(.services.sslInspection.messageBroker);

    .versionDetail."services/messageBroker"=1
    |
    if .services.sslInspection?.messageBroker then (migrate_message_broker) else . end
'

exit 0
