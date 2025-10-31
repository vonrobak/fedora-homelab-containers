#!/usr/bin/env bash
# Relocate Btrfs read-only snapshots into organizer folders within each .snapshots root.
# Usage:
#   sudo ./relocate-btrfs-snapshots.sh             # dry-run on all known roots
#   sudo ./relocate-btrfs-snapshots.sh --apply     # perform changes
#   sudo ./relocate-btrfs-snapshots.sh --root /path/to/.snapshots [--apply]
#   sudo ./relocate-btrfs-snapshots.sh --check     # syntax check only
#   sudo ./relocate-btrfs-snapshots.sh --debug     # verbose logs
set -Eeuo pipefail

DRY_RUN=1
DEBUG=0
SELECTED_ROOT=""
RUN_CHECK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) DRY_RUN=0; shift ;;
    --root)  SELECTED_ROOT="${2:-}"; shift 2 ;;
    --debug) DEBUG=1; shift ;;
    --check) RUN_CHECK=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Resolve the real user's home even under sudo.
get_real_home() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    getent passwd "${SUDO_USER}" | awk -F: '{print $6}'
  else
    getent passwd "$(id -un)" | awk -F: '{print $6}'
  fi
}
REAL_HOME="$(get_real_home)"

DEFAULT_ROOTS=(
  "${REAL_HOME}/.snapshots"
  "/run/media/patriark/WD-18TB/.snapshots"
  "/mnt/btrfs-pool/.snapshots"
)

log() { printf '%s\n' "$*"; }
dbg() { if [[ $DEBUG -eq 1 ]]; then printf '[DEBUG] %s\n' "$*"; fi; }
act() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '[DRY] %s\n' "$*"
  else
    eval "$@"
  fi
}

if [[ $RUN_CHECK -eq 1 ]]; then
  bash -n "$0" && echo "Syntax OK." || { echo "Syntax check failed." >&2; exit 2; }
  exit 0
fi

is_subvol_root() {
  local p="$1"
  btrfs subvolume show -- "$p" >/dev/null 2>&1
}

is_ro_subvol() {
  local p="$1"
  local prop
  if ! prop="$(btrfs property get -ts -- "$p" ro 2>/dev/null)"; then
    return 1
  fi
  [[ "$prop" =~ ro[[:space:]]*=[[:space:]]*true ]]
}

# Extract category from snapshot name.
# Special cases: htpc-home, htpc-root (accepts typos "htpchome", "htpcroot").
# Otherwise use last hyphen-separated token: docs, pics, opptak, multimedia, music, tmp, containers.
extract_category() {
  local name="$1"
  local lname="${name,,}"
  lname="${lname//htpchome/htpc-home}"
  lname="${lname//htpcroot/htpc-root}"
  lname="${lname//htpc\-home/htpc-home}"
  lname="${lname//htpc\-root/htpc-root}"

  if [[ "$lname" == *"htpc-home"* ]]; then echo "htpc-home"; return; fi
  if [[ "$lname" == *"htpc-root"* ]]; then echo "htpc-root"; return; fi

  if [[ "$lname" == *"-"* ]]; then
    echo "${lname##*-}"
  else
    echo ""
  fi
}

# Map category -> organizer folder for a given .snapshots root.
map_category_to_folder() {
  local snaproot="$1" category="$2"
  case "$snaproot" in
    "${REAL_HOME}/.snapshots")
      case "$category" in
        htpc-home) echo "htpc-home"; return ;;
        htpc-root) echo "htpc-root"; return ;;
      esac
      ;;
    "/run/media/patriark/WD-18TB/.snapshots"|"/mnt/btrfs-pool/.snapshots")
      case "$category" in
        htpc-home)  echo "htpc-home"; return ;;
        htpc-root)  echo "htpc-root"; return ;;
        docs)       echo "subvol1-docs"; return ;;
        pics)       echo "subvol2-pics"; return ;;
        opptak)     echo "subvol3-opptak"; return ;;
        multimedia) echo "subvol4-multimedia"; return ;;
        music)      echo "subvol5-music"; return ;;
        tmp)        echo "subvol6-tmp"; return ;;
        containers) echo "subvol7-containers"; return ;;
      esac
      ;;
  esac
  echo ""
}

is_already_in_target() {
  local snaproot="$1" name="$2" path="$3"
  local category targetfolder
  category="$(extract_category "$name")"
  targetfolder="$(map_category_to_folder "$snaproot" "$category")"
  [[ -n "$targetfolder" && "$path" == "$snaproot/$targetfolder/$name" ]]
}

process_snapshot() {
  local snaproot="$1" name="$2" path="$3"

  if is_already_in_target "$snaproot" "$name" "$path"; then
    log "Already placed: $path"
    return 0
  fi

  local category targetfolder parent dest
  category="$(extract_category "$name")"
  if [[ -z "$category" ]]; then
    log "Skip (could not parse category): $path"
    return 0
  fi
  targetfolder="$(map_category_to_folder "$snaproot" "$category")"
  if [[ -z "$targetfolder" ]]; then
    log "Skip (no mapping for category '$category'): $path"
    return 0
  fi
  dbg "name='${name}' -> category='${category}' -> target='${targetfolder}'"

  parent="$snaproot/$targetfolder"
  dest="$parent/$name"

  if [[ ! -d "$parent" ]]; then
    act "mkdir -p -- \"$parent\""
  fi

  if [[ -e "$dest" ]]; then
    if is_subvol_root "$dest"; then
      log "Destination already a subvolume, skipping: $dest"
      return 0
    fi
    if [[ -d "$dest" && -z "$(ls -A -- \"$dest\" 2>/dev/null || true)" ]]; then
      act "rmdir -- \"$dest\""
    else
      log "Destination exists and not an empty dir/subvolume: $dest"
      return 1
    fi
  fi

  log "Snapshot -> $dest"
  act "btrfs subvolume snapshot -r -- \"$path\" \"$dest\""

  log "Delete old: $path"
  act "btrfs subvolume delete -- \"$path\""

  log "Relocated: $name -> $targetfolder"
}

process_root() {
  local snaproot="$1"

  if [[ ! -d "$snaproot" ]]; then
    log "Skipping non-existent root: $snaproot"
    return 0
  fi

  log ""
  log "=== Scanning $snaproot ==="

  shopt -s dotglob nullglob
  local entries=("$snaproot"/*)
  shopt -u dotglob

  if (( ${#entries[@]} == 0 )); then
    log "No entries."
    return 0
  fi

  local entry name
  for entry in "${entries[@]}"; do
    name="$(basename -- "$entry")"

    # Skip organizer dirs
    case "$name" in
      htpc-home|htpc-root|subvol[1-7]-*)
        dbg "Skip organizer dir: $entry"
        continue
        ;;
    esac

    if ! is_subvol_root "$entry"; then
      dbg "Not a subvolume: $entry"
      continue
    fi

    if ! is_ro_subvol "$entry"; then
      log "Skip RW subvolume (not RO snapshot): $entry"
      continue
    fi

    process_snapshot "$snaproot" "$name" "$entry"
  done
}

main() {
  if [[ -n "$SELECTED_ROOT" ]]; then
    process_root "$SELECTED_ROOT"
  else
    local r
    for r in "${DEFAULT_ROOTS[@]}"; do
      process_root "$r"
    done
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    echo
    echo "Dry-run complete. Re-run with --apply to make changes."
  fi
}
main "$@"
