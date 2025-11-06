#!/usr/bin/env python3

import json
import sys
from enum import Enum
from collections import namedtuple

SOURCE_TYPE_CIDR = 0
SOURCE_TYPE_IFACE = 1

Mode = namedtuple("Mode", "mode_code, dns, categories")
AD_MODE = Mode(mode_code=1, dns=None, categories=["ADVERTISEMENT"])
WORK_MODE = Mode(mode_code=2, dns="185.228.168.10", categories=["WORK"])
FAMILY_MODE = Mode(mode_code=3, dns="185.228.168.168", categories=["FAMILY"])


class Rule:
    def __init__(self, source: tuple[int, str]):
        self.source = source
        self.appended_source = set()
        self.included_domains = set()
        self.excluded_domains = set()
        self.modes = set()

    def get_source(self):
        return self.source

    def add_mode(self, mode_codes: int, is_logging: bool):
        self.modes.add(
            (
                mode_codes,
                is_logging,
            )
        )

    def append_source(self, source: tuple[int, str]):
        self.appended_source.add(source)

    def add_included_domains(self, domain: str):
        self.included_domains.add(domain)

    def add_excluded_domains(self, domain: str):
        self.excluded_domains.add(domain)

    def to_dict(self) -> dict:
        mode_codes = {i[0] for i in self.modes}
        return {
            "sourceMACs": [],
            "sourceCIDRs": sorted(
                [
                    source[1]
                    for source in [self.source] + list(self.appended_source)
                    if source[0] == SOURCE_TYPE_CIDR
                ]
            ),
            "sourceInterfaces": sorted(
                [
                    source[1]
                    for source in [self.source] + list(self.appended_source)
                    if source[0] == SOURCE_TYPE_IFACE
                ]
            ),
            "blockConditions": [
                {
                    "includedDomains": sorted(list(self.included_domains)),
                    "excludedDomains": sorted(list(self.excluded_domains)),
                    "categories": getModeCategories(mode[0]),
                    "logging": mode[1],
                }
                for mode in sorted(self.modes)
            ],
            "safeMode": {
                "google": WORK_MODE.mode_code in mode_codes
                or FAMILY_MODE.mode_code in mode_codes,
                "bing": WORK_MODE.mode_code in mode_codes
                or FAMILY_MODE.mode_code in mode_codes,
                "youtube": FAMILY_MODE.mode_code in mode_codes,
            },
        }

    def __eq__(self, other):
        return (
            self.included_domains == other.included_domains
            and self.excluded_domains == other.excluded_domains
            and self.modes == other.modes
        )


def getModeCategories(mode_code: int):
    if mode_code == AD_MODE.mode_code:
        return AD_MODE.categories
    elif mode_code == WORK_MODE.mode_code:
        return WORK_MODE.categories
    elif mode_code == FAMILY_MODE.mode_code:
        return FAMILY_MODE.categories
    return []


def parser_dns_reputation(utm: dict, rule: Rule):
    for entry in utm.get("dnsReputation", []):
        source = rule.get_source()
        if (
            source[0] == SOURCE_TYPE_CIDR
            and source[1] not in entry.get("netAddresses", [])
            or source[0] == SOURCE_TYPE_IFACE
            and source[1] not in entry.get("interfaces", [])
        ):
            continue
        domain = entry.get("domainName", None)
        if domain and entry.get("reputationType", None) == "whitelist":
            rule.add_excluded_domains(domain)
        elif domain and entry.get("reputationType", None) == "blacklist":
            rule.add_included_domains(domain)


def parser_dns_filter_mode(
    source: tuple[int, str],
    dnsFilter_entry: dict,
    is_logging_ad_blocking: bool,
    is_logging_content_filtering: bool,
) -> Rule:
    rule = Rule(source)
    if dnsFilter_entry.get("dnsAddress", None) == WORK_MODE.dns:
        rule.add_mode(WORK_MODE.mode_code, is_logging_content_filtering)
    elif dnsFilter_entry.get("dnsAddress", None) == FAMILY_MODE.dns:
        rule.add_mode(FAMILY_MODE.mode_code, is_logging_content_filtering)
    if dnsFilter_entry.get("adsFilter", False):
        rule.add_mode(AD_MODE.mode_code, is_logging_ad_blocking)
    return rule


def parser_dns_filter(utm: dict) -> list[Rule]:
    is_logging_ad_blocking = utm.get("adBlockingLoggingEnabled", False)
    is_logging_content_filtering = utm.get("contentFilteringLoggingEnabled", False)

    rules = []
    for entry in utm.get("dnsFilter", []):
        for cidr in entry.get("netAddresses", []):
            rules.append(
                parser_dns_filter_mode(
                    (SOURCE_TYPE_CIDR, cidr),
                    entry,
                    is_logging_ad_blocking,
                    is_logging_content_filtering,
                )
            )
        for iface in entry.get("interfaces", []):
            rules.append(
                parser_dns_filter_mode(
                    (SOURCE_TYPE_IFACE, iface),
                    entry,
                    is_logging_ad_blocking,
                    is_logging_content_filtering,
                )
            )
    return rules


def make_dns_resolv_rules(config: dict) -> list[str]:
    utm_config = config.get("services", {}).get("utm", {})
    rules = parser_dns_filter(utm_config)

    for rule in rules:
        parser_dns_reputation(utm_config, rule)

    i = 0
    while i < len(rules):
        remove_list = []
        for j in range(len(rules) - 1, -1, -1):
            if i == j:
                break
            if rules[i] == rules[j]:
                rules[i].append_source(rules[j].get_source())
                remove_list.append(j)
        for j in remove_list:
            del rules[j]
        i += 1

    return [rule.to_dict() for rule in rules]


def migrate_utm(config: dict):
    config["versionDetail"]["services/utm"] = 5
    if not config.get("services", {}).get("utm", None):
        return
    config["services"]["utm"]["dnsResolvRules"] = make_dns_resolv_rules(config)
    config["services"]["utm"].pop("contentFilteringLoggingEnabled", None)
    config["services"]["utm"].pop("adBlockingLoggingEnabled", None)
    config["services"]["utm"].pop("dnsFilter", None)
    config["services"]["utm"].pop("dnsReputation", None)


if __name__ == "__main__":
    udapi_config_path = sys.argv[1]
    config = json.load(open(udapi_config_path))
    migrate_utm(config)
    json.dump(config, open(udapi_config_path, "w"), indent=1)
