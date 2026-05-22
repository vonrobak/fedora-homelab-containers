#!/bin/bash
################################################################################
# filefrag-baseline.sh — BTRFS fragmentation baseline for DB workloads (ADR-029)
#
# Quantifies the "COW defeated by snapshots" antipattern. Run BEFORE and AFTER
# the Phase B migration to measure the fragmentation delta:
#   - subvol7 DBs (COW inside a snapshotted subvolume) = the antipattern; expect
#     high/growing extent counts on hot DB files.
#   - subvol8 DBs (NOCOW, excluded from snapshots) = the reference; expect low,
#     stable extent counts.
#
# Needs root (DB data dirs are container-subuid-owned, mode 700).
# Usage:  sudo bash scripts/filefrag-baseline.sh
################################################################################
set -uo pipefail

TS="$(date +%Y-%m-%d-%H%M)"
OUT="/home/patriark/containers/data/backup-logs/filefrag-baseline-${TS}.txt"

# subvol7 = Phase B migration candidates (COW-in-snapshot); subvol8 = reference
DIRS=(
    "/mnt/btrfs-pool/subvol7-containers/postgresql-immich|subvol7 (candidate)"
    "/mnt/btrfs-pool/subvol7-containers/nextcloud-db/data|subvol7 (candidate)"
    "/mnt/btrfs-pool/subvol7-containers/gathio-db|subvol7 (candidate)"
    "/mnt/btrfs-pool/subvol7-containers/prometheus|subvol7 (candidate)"
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
