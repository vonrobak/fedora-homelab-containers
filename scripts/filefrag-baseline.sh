#!/bin/bash
################################################################################
# filefrag-baseline.sh — BTRFS fragmentation baseline for DB workloads (ADR-029)
#
# Quantifies the "COW defeated by snapshots" antipattern (ADR-029). The Phase B
# migration (executed 2026-06-09) moved the 4 hot DBs subvol7 -> subvol8-db (NOCOW),
# so this now measures all Tier-2 engines in their NOCOW home. Compare the migrated
# DBs against the pre-migration baseline for the before/after delta:
#   - PRE (subvol7, COW-in-snapshot, 2026-05-22): nextcloud oc_filecache.ibd = 11,777
#     extents, gathio max 2,362, immich PG max 1,862
#     (data/backup-logs/filefrag-baseline-2026-05-22-2245.txt).
#   - POST (subvol8, NOCOW): expect low, stable counts like the forgejo/loki references.
#
# Needs root (DB data dirs are container-subuid-owned, mode 700).
# Usage:  sudo bash scripts/filefrag-baseline.sh
################################################################################
set -uo pipefail

TS="$(date +%Y-%m-%d-%H%M)"
OUT="/home/patriark/containers/data/backup-logs/filefrag-baseline-${TS}.txt"

# All Tier-2 engines now live in subvol8-db (NOCOW) after Phase B migration (2026-06-09).
# First 4 = the migrated DBs (compare vs the 2026-05-22 pre-migration baseline);
# forgejo-db + loki = the pre-existing NOCOW references.
DIRS=(
    "/mnt/btrfs-pool/subvol8-db/postgresql-immich|subvol8 (migrated 2026-06-09)"
    "/mnt/btrfs-pool/subvol8-db/nextcloud-db|subvol8 (migrated 2026-06-09)"
    "/mnt/btrfs-pool/subvol8-db/gathio-db|subvol8 (migrated 2026-06-09)"
    "/mnt/btrfs-pool/subvol8-db/prometheus|subvol8 (migrated 2026-06-09)"
    "/mnt/btrfs-pool/subvol8-db/forgejo-db|subvol8 (NOCOW reference)"
    "/mnt/btrfs-pool/subvol8-db/loki|subvol8 (NOCOW reference)"
)

emit() {
    echo "BTRFS fragmentation baseline — ${TS}"
    echo "extents/file: higher = more fragmented. DB random-write files under"
    echo "COW+snapshots accumulate extents; NOCOW (excluded from snapshots) stays flat."
    echo
    for entry in "${DIRS[@]}"; do
        local dir="${entry%%|*}" label="${entry##*|}"
        if [[ ! -d "$dir" ]]; then echo "## ${dir}  [${label}]  — ABSENT"; echo; continue; fi
        # "<extents> <path>" per regular file
        local frag
        frag="$(find "$dir" -type f -print0 2>/dev/null \
            | xargs -0 -r filefrag 2>/dev/null \
            | sed -nE 's/^(.*): ([0-9]+) extents? found$/\2 \1/p')"
        echo "## ${dir}  [${label}]"
        if [[ -z "$frag" ]]; then echo "   (no regular files)"; echo; continue; fi
        local nfiles total max
        nfiles="$(echo "$frag" | wc -l)"
        total="$(echo "$frag" | awk '{s+=$1} END{print s}')"
        max="$(echo "$frag" | awk 'BEGIN{m=0} $1>m{m=$1} END{print m}')"
        awk -v n="$nfiles" -v t="$total" -v m="$max" \
            'BEGIN{printf "   files=%d  total_extents=%d  mean=%.1f  max=%d\n", n, t, (n>0)?t/n:0, m}'
        echo "$frag" | sort -rn | head -5 | awk '{printf "   worst: %6d extents  %s\n", $1, $2}'
        echo
    done
}

mkdir -p "$(dirname "$OUT")"
emit | tee "$OUT"
chmod 644 "$OUT" 2>/dev/null || true
echo "Saved: $OUT"
