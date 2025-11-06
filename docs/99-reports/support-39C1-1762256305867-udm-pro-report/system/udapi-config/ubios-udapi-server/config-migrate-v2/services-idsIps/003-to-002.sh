#!/bin/sh
. "$(dirname "${0}")"/../JQ # include JQ helper scripts

JQA "${1}" '
    def renameCategory(signature):
        if signature<FILTERED> == "3CORESEC" then signature<FILTERED> = ""
        elif signature<FILTERED> == "ACTIVEX" then signature<FILTERED> = "emerging-activex"
        elif signature<FILTERED> == "ADWARE_PUP" then signature<FILTERED> = ""
        elif signature<FILTERED> == "ATTACK_RESPONSE" then signature<FILTERED> = "emerging-attackresponse"
        elif signature<FILTERED> == "BOTCC" then signature<FILTERED> = "botcc"
        elif signature<FILTERED> == "BOTCC.PORTGROUPED" then signature<FILTERED> = "botcc-portgrouped"
        elif signature<FILTERED> == "CHAT" then signature<FILTERED> = "emerging-chat"
        elif signature<FILTERED> == "CIARMY" then signature<FILTERED> = "ciarmy"
        elif signature<FILTERED> == "COINMINER" then signature<FILTERED> = ""
        elif signature<FILTERED> == "COMPROMISED" then signature<FILTERED> = "compromised"
        elif signature<FILTERED> == "CURRENT_EVENTS" then signature<FILTERED> = ""
        elif signature<FILTERED> == "DELETED" then signature<FILTERED> = ""
        elif signature<FILTERED> == "DNS" then signature<FILTERED> = "emerging-dns"
        elif signature<FILTERED> == "DOS" then signature<FILTERED> = "emerging-dos"
        elif signature<FILTERED> == "DROP" then signature<FILTERED> = ""
        elif signature<FILTERED> == "DSHIELD" then signature<FILTERED> = "dshield"
        elif signature<FILTERED> == "EXPLOIT" then signature<FILTERED> = "emerging-exploit"
        elif signature<FILTERED> == "EXPLOIT_KIT" then signature<FILTERED> = ""
        elif signature<FILTERED> == "FTP" then signature<FILTERED> = "emerging-ftp"
        elif signature<FILTERED> == "GAMES" then signature<FILTERED> = "emerging-games"
        elif signature<FILTERED> == "HUNTING" then signature<FILTERED> = ""
        elif signature<FILTERED> == "ICMP" then signature<FILTERED> = "emerging-icmp"
        elif signature<FILTERED> == "ICMP_INFO" then signature<FILTERED> = "emerging-icmpinfo"
        elif signature<FILTERED> == "IMAP" then signature<FILTERED> = "emerging-imap"
        elif signature<FILTERED> == "INAPPROPRIATE" then signature<FILTERED> = "emerging-inappropriate"
        elif signature<FILTERED> == "INFO" then signature<FILTERED> = "emerging-info"
        elif signature<FILTERED> == "JA3" then signature<FILTERED> = ""
        elif signature<FILTERED> == "MALWARE" then signature<FILTERED> = "emerging-malware"
        elif signature<FILTERED> == "MISC" then signature<FILTERED> = "emerging-misc"
        elif signature<FILTERED> == "MOBILE_MALWARE" then signature<FILTERED> = "emerging-mobile"
        elif signature<FILTERED> == "NETBIOS" then signature<FILTERED> = "emerging-netbios"
        elif signature<FILTERED> == "P2P" then signature<FILTERED> = "emerging-p2p"
        elif signature<FILTERED> == "PHISHING" then signature<FILTERED> = ""
        elif signature<FILTERED> == "POLICY" then signature<FILTERED> = "emerging-policy"
        elif signature<FILTERED> == "POP3" then signature<FILTERED> = "emerging-pop3"
        elif signature<FILTERED> == "RPC" then signature<FILTERED> = "emerging-rpc"
        elif signature<FILTERED> == "SCADA" then signature<FILTERED> = "emerging-scada"
        elif signature<FILTERED> == "SCADA_SPECIAL" then signature<FILTERED> = ""
        elif signature<FILTERED> == "SCAN" then signature<FILTERED> = "emerging-scan"
        elif signature<FILTERED> == "SHELLCODE" then signature<FILTERED> = "emerging-shellcode"
        elif signature<FILTERED> == "SMTP" then signature<FILTERED> = "emerging-smtp"
        elif signature<FILTERED> == "SNMP" then signature<FILTERED> = "emerging-snmp"
        elif signature<FILTERED> == "SQL" then signature<FILTERED> = "emerging-sql"
        elif signature<FILTERED> == "TELNET" then signature<FILTERED> = "emerging-telnet"
        elif signature<FILTERED> == "TFTP" then signature<FILTERED> = "emerging-tftp"
        elif signature<FILTERED> == "THREATVIEW_CS_C2" then signature<FILTERED> = ""
        elif signature<FILTERED> == "TOR" then signature<FILTERED> = "tor"
        elif signature<FILTERED> == "user<FILTERED>" then signature<FILTERED> = "emerging-user<FILTERED>"
        elif signature<FILTERED> == "VOIP" then signature<FILTERED> = "emerging-voip"
        elif signature<FILTERED> == "WEB_CLIENT" then signature<FILTERED> = "emerging-webclient"
        elif signature<FILTERED> == "WEB_SERVER" then signature<FILTERED> = "emerging-webserver"
        elif signature<FILTERED> == "WEB_SPECIFIC_APPS" then signature<FILTERED> = "emerging-webapps"
        elif signature<FILTERED> == "WORM" then signature<FILTERED> = "emerging-worm"
        elif signature<FILTERED> == "TROJAN" then signature<FILTERED> = "emerging-trojan"
        elif signature<FILTERED> == "UBIQUITI_CUSTOM" then signature<FILTERED> = "ubiquiti-custom"
        elif signature<FILTERED> == "UBIQUITI_RULES" then signature<FILTERED> = "ubiquiti-rules"
        else signature<FILTERED> = ""
        end
        ;

    def cleanEmptyCategories(idsIps):
        del( idsIps.signature<FILTERED>[]? | select(.category == ""))
        ;
    def migrateIdsIps(config):
        config.services.idsIps.signature<FILTERED>[]? |= renameCategory(config)
        | config.services.idsIps |= cleanEmptyCategories(config)
        ;

    del(.services.idsIps.blockTime)
    |
    del(.services.idsIps.token)
    |
    del(.services.idsIps.deviceID)
    |
    .versionDetail."services/idsIps"=2
    |
    if .services | has("idsIps") then . = migrateIdsIps(.) else . end
'

exit 0
