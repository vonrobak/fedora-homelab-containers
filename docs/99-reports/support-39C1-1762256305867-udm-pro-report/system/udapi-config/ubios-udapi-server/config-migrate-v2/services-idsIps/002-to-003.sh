#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts


JQA "${1}" '
    def renameCategory(signature):
        if signature<FILTERED> == "emerging-activex" then signature<FILTERED> = "ACTIVEX"
        elif signature<FILTERED> == "emerging-attackresponse" then signature<FILTERED> = "ATTACK_RESPONSE"
        elif signature<FILTERED> == "botcc" then signature<FILTERED> = "BOTCC"
        elif signature<FILTERED> == "botcc-portgrouped" then signature<FILTERED> = "BOTCC.PORTGROUPED"
        elif signature<FILTERED> == "emerging-chat" then signature<FILTERED> = "CHAT"
        elif signature<FILTERED> == "ciarmy" then signature<FILTERED> = "CIARMY"
        elif signature<FILTERED> == "compromised" then signature<FILTERED> = "COMPROMISED"
        elif signature<FILTERED> == "emerging-dns" then signature<FILTERED> = "DNS"
        elif signature<FILTERED> == "emerging-dos" then signature<FILTERED> = "DOS"
        elif signature<FILTERED> == "dshield" then signature<FILTERED> = "DSHIELD"
        elif signature<FILTERED> == "emerging-exploit" then signature<FILTERED> = "EXPLOIT"
        elif signature<FILTERED> == "emerging-ftp" then signature<FILTERED> = "FTP"
        elif signature<FILTERED> == "emerging-games" then signature<FILTERED> = "GAMES"
        elif signature<FILTERED> == "emerging-icmp" then signature<FILTERED> = "ICMP"
        elif signature<FILTERED> == "emerging-icmpinfo" then signature<FILTERED> = "ICMP_INFO"
        elif signature<FILTERED> == "emerging-imap" then signature<FILTERED> = "IMAP"
        elif signature<FILTERED> == "emerging-inappropriate" then signature<FILTERED> = "INAPPROPRIATE"
        elif signature<FILTERED> == "emerging-info" then signature<FILTERED> = "INFO"
        elif signature<FILTERED> == "emerging-malware" then signature<FILTERED> = "MALWARE"
        elif signature<FILTERED> == "emerging-misc" then signature<FILTERED> = "MISC"
        elif signature<FILTERED> == "emerging-mobile" then signature<FILTERED> = "MOBILE_MALWARE"
        elif signature<FILTERED> == "emerging-netbios" then signature<FILTERED> = "NETBIOS"
        elif signature<FILTERED> == "emerging-p2p" then signature<FILTERED> = "P2P"
        elif signature<FILTERED> == "emerging-policy" then signature<FILTERED> = "POLICY"
        elif signature<FILTERED> == "emerging-pop3" then signature<FILTERED> = "POP3"
        elif signature<FILTERED> == "emerging-rpc" then signature<FILTERED> = "RPC"
        elif signature<FILTERED> == "emerging-scada" then signature<FILTERED> = "SCADA"
        elif signature<FILTERED> == "emerging-scan" then signature<FILTERED> = "SCAN"
        elif signature<FILTERED> == "emerging-shellcode" then signature<FILTERED> = "SHELLCODE"
        elif signature<FILTERED> == "emerging-smtp" then signature<FILTERED> = "SMTP"
        elif signature<FILTERED> == "emerging-snmp" then signature<FILTERED> = "SNMP"
        elif signature<FILTERED> == "emerging-sql" then signature<FILTERED> = "SQL"
        elif signature<FILTERED> == "emerging-telnet" then signature<FILTERED> = "TELNET"
        elif signature<FILTERED> == "emerging-tftp" then signature<FILTERED> = "TFTP"
        elif signature<FILTERED> == "tor" then signature<FILTERED> = "TOR"
        elif signature<FILTERED> == "emerging-user<FILTERED>" then signature<FILTERED> = "user<FILTERED>"
        elif signature<FILTERED> == "emerging-voip" then signature<FILTERED> = "VOIP"
        elif signature<FILTERED> == "emerging-webclient" then signature<FILTERED> = "WEB_CLIENT"
        elif signature<FILTERED> == "emerging-webserver" then signature<FILTERED> = "WEB_SERVER"
        elif signature<FILTERED> == "emerging-webapps" then signature<FILTERED> = "WEB_SPECIFIC_APPS"
        elif signature<FILTERED> == "emerging-worm" then signature<FILTERED> = "WORM"
        elif signature<FILTERED> == "emerging-trojan" then signature<FILTERED> = "TROJAN"
        elif signature<FILTERED> == "spamhaus" then signature<FILTERED> = ""
        elif signature<FILTERED> == "ubiquiti-custom" then signature<FILTERED> = "UBIQUITI_CUSTOM"
        elif signature<FILTERED> == "ubiquiti-rules" then signature<FILTERED> = "UBIQUITI_RULES"
        else signature<FILTERED> = ""
        end
        ;

    def cleanEmptyCategories(idsIps):
        del( idsIps.signature<FILTERED>[]? | select(.category == ""))
        ;

    def migrateIdsIps(config):
        config.services.idsIps.blockTime=300
        | config.services.idsIps.deviceID=(config.services.utm.deviceID // "")
        | config.services.idsIps.token=(<FILTERED> // "")
        | config.services.idsIps.signature<FILTERED>[]? |= renameCategory(config)
        | config.services.idsIps |= cleanEmptyCategories(config)
        ;

    .versionDetail."services/idsIps"=3
    |
    if .services | has("idsIps") then . = migrateIdsIps(.) else . end
'

exit 0
