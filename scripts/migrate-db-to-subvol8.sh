#!/bin/bash
################################################################################
# migrate-db-to-subvol8.sh — Phase B offline DB migration tool (ADR-029)
#
# Moves a database's data dir from subvol7-containers (COW, snapshotted — the
# fragmentation antipattern) into subvol8-db (NOCOW, excluded from snapshots).
# This is the riskiest storage operation in the homelab, so the tool is
# defensive: DRY-RUN BY DEFAULT, --execute required for any mutation, hard
# no-reflink copy with post-copy verification, ownership-preserving (no ACLs
# needed — subvol8-db is o+x and the container owns its data dir, exactly like
# the existing forgejo-db tenant), health-gated source retention, real rollback.
#
# RUN AS: your normal user (patriark) — podman/systemctl run natively; the tool
# uses sudo only for the filesystem ops on subuid-owned data. Prime sudo first.
#
# PRECONDITION: run inside the offline window — `scripts/update-before-reboot.sh`
# (graceful-shutdown) must have stopped the containers. The tool refuses to
# migrate a service that is still running.
#
# Usage:
#   migrate-db-to-subvol8.sh list
#   migrate-db-to-subvol8.sh preflight <svc>
#   migrate-db-to-subvol8.sh migrate  <svc> [--execute] [--yes]
#   migrate-db-to-subvol8.sh verify   <svc>
#   migrate-db-to-subvol8.sh rollback <svc> [--execute] [--yes]
#   migrate-db-to-subvol8.sh cleanup  <svc> [--execute]   # after 14d, delete .pre-migration
#
# Suggested order (small -> large): gathio-db nextcloud-db prometheus postgresql-immich
################################################################################
set -uo pipefail

REPO="${HOME}/containers"
SUBVOL8="/mnt/btrfs-pool/subvol8-db"
STATE_DIR="${REPO}/data/backup-logs/db-migration-state"
DATE="$(date +%Y-%m-%d)"

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# --- service config: src data dir | quadlet | space-separated secrets ---------
# dst is always $SUBVOL8/<svc> (single level → simple traversal). The quadlet
# Volume= line's source path is rewritten src -> dst (mount point unchanged).
declare -A SRC QUADLET SECRETS
SRC[postgresql-immich]="/mnt/btrfs-pool/subvol7-containers/postgresql-immich"
SRC[nextcloud-db]="/mnt/btrfs-pool/subvol7-containers/nextcloud-db/data"
SRC[gathio-db]="/mnt/btrfs-pool/subvol7-containers/gathio-db"
SRC[prometheus]="/mnt/btrfs-pool/subvol7-containers/prometheus"
QUADLET[postgresql-immich]="${REPO}/quadlets/postgresql-immich.container"
QUADLET[nextcloud-db]="${REPO}/quadlets/nextcloud-db.container"
QUADLET[gathio-db]="${REPO}/quadlets/gathio-db.container"
QUADLET[prometheus]="${REPO}/quadlets/prometheus.container"
SECRETS[postgresql-immich]="postgres-password"
SECRETS[nextcloud-db]="nextcloud_db_root_password nextcloud_db_password"
SECRETS[gathio-db]="gathio_mongodb_password"
SECRETS[prometheus]="ha-prometheus-token"

EXECUTE=0
ASSUME_YES=0

# --- logging ------------------------------------------------------------------
c_red=$'\033[0;31m'; c_grn=$'\033[0;32m'; c_yel=$'\033[1;33m'; c_cyn=$'\033[0;36m'; c_n=$'\033[0m'
log()  { printf '%s[%s]%s %s\n' "$2" "$1" "$c_n" "${*:3}" >&2; }
info() { log INFO  "$c_cyn" "$@"; }
ok()   { log OK    "$c_grn" "$@"; }
warn() { log WARN  "$c_yel" "$@"; }
die()  { log ERR   "$c_red" "$@"; exit 1; }
dry()  { log DRY   "$c_yel" "$@"; }

# run a mutating command (honors dry-run)
run() { if [[ $EXECUTE -eq 1 ]]; then info "run: $*"; "$@"; else dry "$*"; fi; }

valid_svc() { [[ -n "${SRC[$1]:-}" ]] || die "unknown service '$1'. Known: ${!SRC[*]}"; }
dst_of()    { echo "${SUBVOL8}/$1"; }
premig_of() { echo "${SRC[$1]}.pre-migration-${DATE}"; }

container_running() { systemctl --user is-active --quiet "$1.service"; }

wait_healthy() {  # wait_healthy <container>  (up to ~120s)
    local c="$1" i
    for i in $(seq 1 60); do
        podman healthcheck run "$c" >/dev/null 2>&1 && return 0
        sleep 2
    done
    return 1
}

# --- preflight (read-only) ----------------------------------------------------
cmd_preflight() {
    local svc="$1"; valid_svc "$svc"
    local src="${SRC[$svc]}" dst; dst="$(dst_of "$svc")"
    local q="${QUADLET[$svc]}" fail=0
    info "Preflight: $svc"
    info "  source : $src"
    info "  target : $dst"
    info "  quadlet: $q"

    [[ -d "$SUBVOL8" ]] || { warn "  subvol8-db missing"; fail=1; }
    btrfs subvolume show "$SUBVOL8" >/dev/null 2>&1 && ok "  subvol8-db is a subvolume" || { warn "  subvol8-db is NOT a subvolume"; fail=1; }
    sudo test -d "$src" && ok "  source dir exists" || { warn "  source dir missing"; fail=1; }
    if sudo test -e "$dst"; then warn "  target already exists ($dst) — migrate would refuse"; fail=1; else ok "  target does not exist yet"; fi
    [[ -f "$q" ]] && grep -q "^Volume=${src}:" "$q" && ok "  quadlet Volume= line found" || { warn "  quadlet Volume=${src}: line NOT found"; fail=1; }

    if container_running "$svc"; then warn "  $svc is RUNNING — run graceful-shutdown first (offline window)"; fail=1; else ok "  $svc is stopped (offline)"; fi

    local subuid; subuid="$(sudo stat -c %u "$src" 2>/dev/null)"
    info "  data owned by host uid (subuid): ${subuid:-?} — ownership is preserved on copy (no ACLs needed; subvol8-db is o+x)"

    # space check
    local need avail
    need="$(sudo du -sb "$src" 2>/dev/null | cut -f1)"
    avail="$(df -B1 --output=avail "$SUBVOL8" | tail -1 | tr -d ' ')"
    info "  size to copy: $(numfmt --to=iec "${need:-0}")  | free on pool: $(numfmt --to=iec "${avail:-0}")"
    [[ "${avail:-0}" -gt "$(( ${need:-0} * 2 ))" ]] && ok "  ample free space" || warn "  check free space (need ~2x for safety)"

    # ADR-028: secrets resolve at runtime?
    local s
    for s in ${SECRETS[$svc]}; do
        if podman run --rm --secret "$s" alpine true >/dev/null 2>&1; then ok "  secret resolves: $s"; else warn "  secret FAILS to mount: $s (ADR-028 — fix before migrating)"; fail=1; fi
    done

    if [[ $fail -eq 0 ]]; then
        ok "Preflight PASS for $svc"
    elif [[ $EXECUTE -eq 1 ]]; then
        die "Preflight FAILED for $svc — resolve the warnings above before --execute"
    else
        warn "Preflight has warnings for $svc (above) — must be clean before --execute"
    fi
}

# --- verify (read-only) -------------------------------------------------------
cmd_verify() {
    local svc="$1"; valid_svc "$svc"
    local dst; dst="$(dst_of "$svc")"
    sudo test -d "$dst" || die "target $dst does not exist — nothing migrated?"
    info "Verify: $svc ($dst)"
    # NOCOW
    sudo lsattr -d "$dst" 2>/dev/null | grep -q 'C' && ok "  target dir has +C (NOCOW)" || warn "  target dir MISSING +C"
    local nc; nc="$(sudo find "$dst" -type f 2>/dev/null | head -50 | while read -r f; do sudo lsattr "$f" 2>/dev/null; done | grep -vc 'C------' )"
    [[ "${nc:-0}" -eq 0 ]] && ok "  sampled files all NOCOW" || warn "  ${nc} sampled files missing +C"
    # no shared extents (reflink guard)
    local big shared
    big="$(sudo find "$dst" -type f -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
    if [[ -n "$big" ]]; then
        shared="$(sudo filefrag -v "$big" 2>/dev/null | grep -c shared)"
        [[ "${shared:-0}" -eq 0 ]] && ok "  largest file has no shared extents (no reflink): $(basename "$big")" || die "  SHARED EXTENTS on $big — reflink leaked, NOCOW is defeated"
    fi
    # health
    if container_running "$svc"; then
        if podman healthcheck run "$svc" >/dev/null 2>&1; then ok "  $svc healthy"; else warn "  $svc running but healthcheck failing"; fi
    else
        warn "  $svc not running (start it to verify health)"
    fi
    ok "Verify complete for $svc"
}

# --- migrate ------------------------------------------------------------------
cmd_migrate() {
    local svc="$1"; valid_svc "$svc"
    local src="${SRC[$svc]}" dst q premig
    dst="$(dst_of "$svc")"; q="${QUADLET[$svc]}"; premig="$(premig_of "$svc")"

    cmd_preflight "$svc"   # hard-gates on failure

    if [[ $EXECUTE -ne 1 ]]; then
        info "── DRY RUN plan for $svc (pass --execute to run) ──"
        dry "mkdir -p $dst && chattr -m $dst && chattr +C $dst"
        dry "sudo rsync -aHX --numeric-ids --no-inplace $src/ $dst/   (NO --reflink)"
        dry "verify: sudo lsattr -d $dst (expect C); sudo filefrag largest (expect no shared); size match"
        dry "cp $q ${q}.pre-migration-${DATE}  &&  sed Volume= $src: -> $dst:"
        dry "systemctl --user daemon-reload && systemctl --user start $svc && wait healthy"
        dry "mv $src -> $premig   (retain 14d; source untouched as rollback)"
        return 0
    fi

    if [[ $ASSUME_YES -ne 1 ]]; then
        read -r -p "Type '$svc' to confirm migration: " ans
        [[ "$ans" == "$svc" ]] || die "confirmation mismatch — aborted"
    fi

    sudo test -e "$dst" && die "target $dst already exists — refusing to overwrite"

    # 1. target dir, NOCOW BEFORE any data (m and +C are mutually exclusive → -m first)
    run mkdir -p "$dst"
    run chattr -m "$dst"
    run chattr +C "$dst"
    sudo lsattr -d "$dst" | grep -q 'C' || die "could not set +C on $dst (m flag still set?)"
    ok "target prepared NOCOW: $dst"

    # 2. ownership-preserving copy. NO --reflink, NO --inplace.
    run sudo rsync -aHX --numeric-ids --no-inplace "$src/" "$dst/"

    # 3. verify integrity before we touch the live config
    local ssz dsz
    ssz="$(sudo du -sb "$src" | cut -f1)"; dsz="$(sudo du -sb "$dst" | cut -f1)"
    info "size: source=$(numfmt --to=iec "$ssz")  target=$(numfmt --to=iec "$dsz")"
    local big shared
    big="$(sudo find "$dst" -type f -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
    if [[ -n "$big" ]]; then
        shared="$(sudo filefrag -v "$big" 2>/dev/null | grep -c shared)"
        [[ "${shared:-0}" -eq 0 ]] || { warn "SHARED EXTENTS detected — removing target, aborting"; sudo rm -rf "$dst"; die "reflink leaked into $dst"; }
    fi
    sudo lsattr -d "$dst" | grep -q 'C' || { sudo rm -rf "$dst"; die "post-copy: target lost +C — aborted"; }
    ok "copy verified (NOCOW, no shared extents)"

    # 4. repoint the quadlet (backup first)
    run cp "$q" "${q}.pre-migration-${DATE}"
    run sed -i "/^Volume=/ s|${src}:|${dst}:|" "$q"
    grep -q "^Volume=${dst}:" "$q" || die "quadlet rewrite failed — check $q (backup at ${q}.pre-migration-${DATE})"
    ok "quadlet repointed: $q"

    # 5. start + health-gate
    run systemctl --user daemon-reload
    run systemctl --user start "$svc.service"
    if wait_healthy "$svc"; then
        ok "$svc is healthy on the new path"
    else
        warn "$svc did NOT become healthy — rolling back the quadlet (data on both paths is intact)"
        run cp "${q}.pre-migration-${DATE}" "$q"
        run systemctl --user daemon-reload
        run systemctl --user restart "$svc.service"
        die "$svc unhealthy after migration — reverted quadlet; target $dst left for inspection; SOURCE UNTOUCHED at $src"
    fi

    # 6. retain source as rollback artifact (only after health passes)
    run mv "$src" "$premig"
    ok "source retained at $premig (delete after 14d with: $0 cleanup $svc --execute)"

    # 7. record state
    mkdir -p "$STATE_DIR"
    if [[ $EXECUTE -eq 1 ]]; then
        cat > "${STATE_DIR}/${svc}.migrated" <<EOF
date=${DATE}
src=${src}
dst=${dst}
premig=${premig}
quadlet=${q}
quadlet_backup=${q}.pre-migration-${DATE}
EOF
    fi
    ok "MIGRATED $svc → subvol8-db. Run: $0 verify $svc"
}

# --- rollback -----------------------------------------------------------------
cmd_rollback() {
    local svc="$1"; valid_svc "$svc"
    local state="${STATE_DIR}/${svc}.migrated"
    [[ -f "$state" ]] || die "no migration state for $svc ($state) — nothing to roll back"
    # shellcheck disable=SC1090
    source "$state"
    info "Rollback $svc: restore $premig → $src, revert $quadlet"
    sudo test -d "$premig" || die "pre-migration source $premig missing — cannot roll back safely"

    if [[ $EXECUTE -ne 1 ]]; then
        dry "systemctl --user stop $svc"
        dry "cp $quadlet_backup $quadlet (revert Volume=)"
        dry "sudo rm -rf $dst"
        dry "mv $premig $src"
        dry "systemctl --user daemon-reload && start $svc && wait healthy"
        return 0
    fi
    if [[ $ASSUME_YES -ne 1 ]]; then
        read -r -p "Type '$svc' to confirm ROLLBACK: " ans; [[ "$ans" == "$svc" ]] || die "aborted"
    fi

    run systemctl --user stop "$svc.service"
    run cp "$quadlet_backup" "$quadlet"
    run sudo rm -rf "$dst"
    run mv "$premig" "$src"
    run systemctl --user daemon-reload
    run systemctl --user start "$svc.service"
    if wait_healthy "$svc"; then ok "$svc rolled back and healthy on $src"; else die "$svc unhealthy after rollback — investigate"; fi
    run rm -f "$state"
}

# --- cleanup (post-retention) -------------------------------------------------
cmd_cleanup() {
    local svc="$1"; valid_svc "$svc"
    local state="${STATE_DIR}/${svc}.migrated"
    [[ -f "$state" ]] || die "no migration state for $svc"
    # shellcheck disable=SC1090
    source "$state"
    sudo test -d "$premig" || { warn "$premig already gone"; exit 0; }
    if [[ $EXECUTE -ne 1 ]]; then dry "sudo rm -rf $premig  (and rm $state)"; return 0; fi
    if [[ $ASSUME_YES -ne 1 ]]; then read -r -p "Delete pre-migration source $premig? type '$svc': " ans; [[ "$ans" == "$svc" ]] || die "aborted"; fi
    run sudo rm -rf "$premig"
    ok "removed $premig — migration of $svc finalized"
}

cmd_list() {
    info "Phase B migration candidates (suggested order: gathio-db nextcloud-db prometheus postgresql-immich):"
    local svc
    for svc in "${!SRC[@]}"; do
        local mark="  "; [[ -f "${STATE_DIR}/${svc}.migrated" ]] && mark="✓ "
        printf '  %s%-20s %s  ->  %s\n' "$mark" "$svc" "${SRC[$svc]}" "$(dst_of "$svc")"
    done
}

# --- dispatch -----------------------------------------------------------------
[[ $# -ge 1 ]] || { grep -E '^#( |!)' "$0" | sed 's/^#//' | head -40; exit 0; }
CMD="$1"; shift
SVC=""
for a in "$@"; do
    case "$a" in
        --execute) EXECUTE=1 ;;
        --yes) ASSUME_YES=1 ;;
        -*) die "unknown flag $a" ;;
        *) SVC="$a" ;;
    esac
done

case "$CMD" in
    list)     cmd_list ;;
    preflight) [[ -n "$SVC" ]] || die "need a service"; cmd_preflight "$SVC" ;;
    migrate)  [[ -n "$SVC" ]] || die "need a service"; cmd_migrate "$SVC" ;;
    verify)   [[ -n "$SVC" ]] || die "need a service"; cmd_verify "$SVC" ;;
    rollback) [[ -n "$SVC" ]] || die "need a service"; cmd_rollback "$SVC" ;;
    cleanup)  [[ -n "$SVC" ]] || die "need a service"; cmd_cleanup "$SVC" ;;
    *) die "unknown command '$CMD' (list|preflight|migrate|verify|rollback|cleanup)" ;;
esac
