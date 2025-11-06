#!/usr/bin/env python3

import json
import sys
from enum import Enum
from collections import namedtuple

SOURCE_TYPE_CIDR = 0
SOURCE_TYPE_IFACE = 1

Mode = namedtuple("Mode", "mode_code, dns, categories")
FAKE_MODE = Mode(mode_code=0, dns="203.0.113.1", categories=None)
AD_MODE = Mode(mode_code=1, dns=None, categories={"ADVERTISEMENT"})
WORK_MODE = Mode(mode_code=2, dns="185.228.168.10", categories={"WORK"})
FAMILY_MODE = Mode(mode_code=3, dns="185.228.168.168", categories={"FAMILY"})


def parser_dns_resolv_rules(config: dict) -> tuple[list[dict], list[dict], bool, bool]:
    dns_resolv_rules_config = (
        config.get("services", {}).get("utm", {}).get("dnsResolvRules", [])
    )

    dns_filter_rules = []
    dns_reputation_rules = []
    whitelist = {}
    blacklist = {}
    content_filtering_logging_enabled = False
    ad_blocking_logging_enabled = False

    for rule in dns_resolv_rules_config:
        cidrs = rule.get("sourceCIDRs", [])
        ifaces = rule.get("sourceInterfaces", [])
        adsFilter = False
        contentFilterMode = FAKE_MODE
        blockCfg = rule.get("blockConditions", [])
        for entry in blockCfg:
            included_domains = entry.get("includedDomains", [])
            excluded_domains = entry.get("excludedDomains", [])
            categories = set(entry.get("categories", []))
            is_migratable = False
            if not adsFilter and AD_MODE.categories.issubset(categories):
                adsFilter = True
                ad_blocking_logging_enabled = entry.get("logging", False)
                is_migratable = True
            if contentFilterMode == FAKE_MODE and FAMILY_MODE.categories.issubset(
                categories
            ):
                contentFilterMode = FAMILY_MODE
                content_filtering_logging_enabled = entry.get("logging", False)
                is_migratable = True
            elif contentFilterMode == FAKE_MODE and WORK_MODE.categories.issubset(
                categories
            ):
                contentFilterMode = WORK_MODE
                content_filtering_logging_enabled = entry.get("logging", False)
                is_migratable = True

            if not is_migratable:
                continue

            for domain in included_domains:
                if domain not in blacklist:
                    blacklist[domain] = {
                        SOURCE_TYPE_CIDR: set(),
                        SOURCE_TYPE_IFACE: set(),
                    }
                blacklist[domain][SOURCE_TYPE_CIDR] |= set(cidrs)
                blacklist[domain][SOURCE_TYPE_IFACE] |= set(ifaces)

            for domain in excluded_domains:
                if domain not in whitelist:
                    whitelist[domain] = {
                        SOURCE_TYPE_CIDR: set(),
                        SOURCE_TYPE_IFACE: set(),
                    }
                whitelist[domain][SOURCE_TYPE_CIDR] |= set(cidrs)
                whitelist[domain][SOURCE_TYPE_IFACE] |= set(ifaces)

        for entry in dns_filter_rules:
            if (
                entry["adsFilter"] == adsFilter
                and entry["dnsAddress"] == contentFilterMode.dns
            ):
                entry["netAddresses"] = sorted(
                    list(set(entry["netAddresses"]) | set(cidrs))
                )
                entry["interfaces"] = sorted(
                    list(set(entry["interfaces"]) | set(ifaces))
                )
                break
        else:
            dns_filter_rules.append(
                {
                    "adsFilter": adsFilter,
                    "dnsAddress": contentFilterMode.dns,
                    "netAddresses": cidrs,
                    "interfaces": ifaces,
                }
            )

    for key, <FILTERED> in whitelist.items():
        dns_reputation_rules.append(
            {
                "domainName": key,
                "netAddresses": sorted(list(value[SOURCE_TYPE_CIDR])),
                "interfaces": sorted(list(value[SOURCE_TYPE_IFACE])),
                "reputationType": "whitelist",
            }
        )

    for key, <FILTERED> in blacklist.items():
        dns_reputation_rules.append(
            {
                "domainName": key,
                "netAddresses": sorted(list(value[SOURCE_TYPE_CIDR])),
                "interfaces": sorted(list(value[SOURCE_TYPE_IFACE])),
                "reputationType": "blacklist",
            }
        )

    return (
        dns_filter_rules,
        dns_reputation_rules,
        ad_blocking_logging_enabled,
        content_filtering_logging_enabled,
    )


def migrate_utm(config: dict):
    config["versionDetail"]["services/utm"] = 4
    if not config.get("services", {}).get("utm", None):
        return
    (
        dns_filter_rules,
        dns_reputation_rules,
        ad_blocking_logging_enabled,
        content_filtering_logging_enabled,
    ) = parser_dns_resolv_rules(config)
    config["services"]["utm"]["adBlockingLoggingEnabled"] = ad_blocking_logging_enabled
    config["services"]["utm"][
        "contentFilteringLoggingEnabled"
    ] = content_filtering_logging_enabled
    config["services"]["utm"]["dnsFilter"] = dns_filter_rules
    config["services"]["utm"]["dnsReputation"] = dns_reputation_rules
    config["services"]["utm"].pop("dnsResolvRules", None)


if __name__ == "__main__":
    udapi_config_path = sys.argv[1]
    config = json.load(open(udapi_config_path))
    migrate_utm(config)
    json.dump(config, open(udapi_config_path, "w"), indent=1)
