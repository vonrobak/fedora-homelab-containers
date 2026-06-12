#!/bin/bash
# audit-dump-coverage.sh — ADR-029 / L-019 dump-coverage erosion guard (WP2, 2026-06-12)
#
# db-dump.sh has a hardcoded ENGINES=() array: a new Tier-2 database that is
# never added there (and to db-restore-test.sh) gets ZERO backup with ZERO
# warning — exactly the forgejo-db/loki gap that motivated ADR-029. This script
# closes the loop mechanically:
#
#   EXPECTED = quadlets running a real DB engine image (postgres|mariadb|mongo|mysql)
#            ∪ top-level dirs on /mnt/btrfs-pool/subvol8-db (ADR-029 DB domicile)
#   COVERED  = ENGINES array parsed live from db-dump.sh (single source of truth)
#   GAP      = EXPECTED − COVERED − EXCEPTIONS
#
# EXCEPTIONS are *recorded decisions*, not conveniences — each needs a rationale:
#   loki — Tier 3 / discard-and-reingest by design (ADR-029; nightly dump froze
#          it ~15 min on a cold cache and log data is not source-of-truth).
#
# Output: textfile metrics (node_exporter textfile collector, same channel as
# db-dumps.prom). Labels use database= per the established db_dump_* scheme —
# NOT a service= label (L-045: that clobbers/collides in the inhibit rules).
# Alerts: DbDumpCoverageGap / DbDumpCoverageAuditStale in db-dump-alerts.yml.
#
# Wiring: ExecStartPost=-%h/containers/scripts/audit-dump-coverage.sh in
# db-dump.service ("-" so a coverage gap flags via metrics/alerts without
# marking the dump run itself failed). Exit 1 on gap for ad-hoc / CI use.

set -euo pipefail

QUADLET_DIR="${HOME}/containers/quadlets"
DB_DUMP_SCRIPT="${HOME}/containers/scripts/db-dump.sh"
DB_SUBVOL="/mnt/btrfs-pool/subvol8-db"
METRICS_DIR="${HOME}/containers/data/backup-metrics"
METRICS_FILE="${METRICS_DIR}/dump-coverage.prom"

EXCEPTIONS=(loki)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] ${*:2}" >&2; }

# --- COVERED: parse ENGINES=( ... ) from db-dump.sh -----------------------------
mapfile -t COVERED < <(grep -oP '^ENGINES=\(\K[^)]+' "$DB_DUMP_SCRIPT" | tr ' ' '\n' | grep -v '^$')
if [[ ${#COVERED[@]} -eq 0 ]]; then
    log ERROR "could not parse ENGINES array from $DB_DUMP_SCRIPT"
    exit 2
fi

# --- EXPECTED --------------------------------------------------------------------
declare -A EXPECTED

# (a) quadlets running real DB engine images. The [@:] anchor after the engine
# name keeps exporters out (e.g. .../postgres-exporter@... must not match).
for f in "$QUADLET_DIR"/*.container; do
    img="$(grep -oP '^Image=\K.*' "$f" || true)"
    [[ -z "$img" ]] && continue
    if [[ "$img" =~ /(postgres|mariadb|mongo|mysql)[@:] ]]; then
        name="$(grep -oP '^ContainerName=\K.*' "$f" || basename "$f" .container)"
        EXPECTED["$name"]="quadlet:$(basename "$f")"
    fi
done

# (b) DB-class data domiciles on subvol8-db (ADR-029)
if [[ -d "$DB_SUBVOL" ]]; then
    for d in "$DB_SUBVOL"/*/; do
        [[ -d "$d" ]] || continue
        EXPECTED["$(basename "$d")"]="subvol8-db"
    done
fi

# --- GAP ---------------------------------------------------------------------------
GAPS=()
for svc in "${!EXPECTED[@]}"; do
    covered=0
    for c in "${COVERED[@]}"; do [[ "$svc" == "$c" ]] && covered=1 && break; done
    for e in "${EXCEPTIONS[@]}"; do [[ "$svc" == "$e" ]] && covered=1 && break; done
    [[ $covered -eq 0 ]] && GAPS+=("$svc")
done

# --- report + metrics ----------------------------------------------------------------
mkdir -p "$METRICS_DIR"
{
    echo "# HELP db_dump_coverage_gap DB-like service/data dir not covered by db-dump.sh ENGINES (1=uncovered)"
    echo "# TYPE db_dump_coverage_gap gauge"
    for g in "${GAPS[@]+"${GAPS[@]}"}"; do
        echo "db_dump_coverage_gap{database=\"$g\",origin=\"${EXPECTED[$g]}\"} 1"
    done
    echo "# HELP db_dump_coverage_gap_total Number of uncovered DB-like services"
    echo "# TYPE db_dump_coverage_gap_total gauge"
    echo "db_dump_coverage_gap_total ${#GAPS[@]}"
    echo "# HELP db_dump_coverage_audit_timestamp Unix timestamp of last coverage audit"
    echo "# TYPE db_dump_coverage_audit_timestamp gauge"
    echo "db_dump_coverage_audit_timestamp $(date +%s)"
} > "${METRICS_FILE}.tmp"
mv "${METRICS_FILE}.tmp" "$METRICS_FILE"

if [[ ${#GAPS[@]} -gt 0 ]]; then
    log WARN "dump-coverage GAP: ${GAPS[*]} (in ${#EXPECTED[@]} expected, ${#COVERED[@]} covered)"
    log WARN "fix: add to ENGINES in db-dump.sh + db-restore-test.sh, or record a decided exception here"
    exit 1
fi
log INFO "dump coverage OK: ${#EXPECTED[@]} DB-like services/dirs all covered or excepted"
exit 0
