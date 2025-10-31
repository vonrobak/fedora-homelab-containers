#!/usr/bin/env bash
cap "blkid" bash -lc 'blkid' > "$OUTDIR/blkid.txt"
cap "mounts" bash -lc 'mount' > "$OUTDIR/mount.txt"
cap "df" bash -lc 'df -hT' > "$OUTDIR/df.txt"
cap "fstab" bash -lc 'cat /etc/fstab' > "$OUTDIR/fstab.txt"
cap "cryptsetup" bash -lc 'for m in /dev/mapper/*; do echo "--- $m"; cryptsetup status "$m"; done' > "$OUTDIR/cryptsetup.txt"
cap "btrfs-fi-show" bash -lc 'btrfs fi show' > "$OUTDIR/btrfs/fi-show.txt"
cap "btrfs-usage-root" bash -lc 'btrfs fi usage -T /' > "$OUTDIR/btrfs/usage-root.txt"
for m in $(awk '$3=="btrfs"{print $2}' /proc/self/mounts | sort -u); do
safe=$(echo "$m" | tr '/' '_');
cap "btrfs-usage-$safe" bash -lc "btrfs fi usage -T '$m'" > "$OUTDIR/btrfs/usage-$safe.txt" || true
cap "btrfs-subvols-$safe" bash -lc "btrfs subvolume list -puq '$m'" > "$OUTDIR/btrfs/subvols-$safe.txt" || true
cap "btrfs-quota-$safe" bash -lc "btrfs quota show -g '$m'" > "$OUTDIR/btrfs/quota-$safe.txt" || true
cap "btrfs-scrub-$safe" bash -lc "journalctl --no-pager -u btrfs-scrub@* | tail -n 200" > "$OUTDIR/btrfs/scrub-$safe.txt" || true
done


# 3) SMART (best effort)
which smartctl >/dev/null 2>&1 && {
for d in /dev/sd? /dev/nvme?n1; do
[ -e "$d" ] || continue
cap "smart-$d" smartctl -H -A "$d" > "$OUTDIR/smart-$(basename "$d").txt" || true
done
}


# 4) Podman / networks / containers
cap "podman-info" bash -lc 'podman info' > "$OUTDIR/podman/info.json"
cap "podman-net-ls" bash -lc 'podman network ls' > "$OUTDIR/podman/net-ls.txt"
cap "podman-net-inspect" bash -lc 'for n in $(podman network ls --format {{.Name}}); do echo "--- $n"; podman network inspect $n; done' > "$OUTDIR/podman/net-inspect.txt"
cap "podman-ps" bash -lc 'podman ps --format "table {{.Names}}\t{{.Image}}\t{{.Networks}}\t{{.Status}}"' > "$OUTDIR/podman/ps.txt"
cap "podman-volumes" bash -lc 'podman volume ls' > "$OUTDIR/podman/volumes.txt"


# Inspect key services if present
for s in traefik tinyauth nextcloud mariadb redis crowdsec; do
podman container exists "$s" && podman inspect "$s" | redact > "$OUTDIR/podman/inspect-$s.json" || true
systemctl --user is-enabled container-$s.service >/dev/null 2>&1 && systemctl --user status container-$s.service --no-pager > "$OUTDIR/systemd/$s.txt" || true
done


# 5) Configs (paths are common defaults; skip if missing)
copy_if() { [ -r "$1" ] && (redact < "$1" > "$OUTDIR/configs/$(basename "$1").redacted" || true); }
copy_if /etc/containers/containers.conf
copy_if /etc/containers/storage.conf
copy_if "$HOME"/.config/containers/containers.conf
copy_if /etc/traefik/traefik.yml
copy_if /etc/traefik/traefik.toml
copy_if /etc/traefik/dynamic.yml
copy_if /etc/traefik/dynamic.toml
copy_if /etc/tinyauth/config.yml
copy_if /etc/crowdsec/config.yaml
copy_if /etc/crowdsec/bouncers/crowdsec-traefik-bouncer.yaml


# 6) Firewall / SELinux / DNS / routing
cap "firewalld" bash -lc 'firewall-cmd --state; firewall-cmd --get-default-zone; firewall-cmd --list-all' > "$OUTDIR/net/firewalld.txt" || true
cap "selinux" bash -lc 'getenforce; sestatus' > "$OUTDIR/net/selinux.txt" || true
cap "ip-addr" bash -lc 'ip -br addr' > "$OUTDIR/net/ip-addr.txt"
cap "ip-route" bash -lc 'ip route' > "$OUTDIR/net/ip-route.txt"
cap "resolvectl" bash -lc 'resolvectl status' > "$OUTDIR/net/resolvectl.txt" || true


# 7) Timers / backups / cron
cap "systemd-timers" bash -lc 'systemctl list-timers --all --no-pager' > "$OUTDIR/systemd/timers.txt"
cap "user-timers" bash -lc 'systemctl --user list-timers --all --no-pager' > "$OUTDIR/systemd/user-timers.txt"
cap "crontab-root" bash -lc 'crontab -l' > "$OUTDIR/systemd/crontab-root.txt" || true
cap "crontab-user" bash -lc 'crontab -u "$USER" -l' > "$OUTDIR/systemd/crontab-user.txt" || true


# 8) Nextcloud (if already present)
if podman container exists nextcloud; then
cap "nextcloud-occ-status" bash -lc 'podman exec -it nextcloud occ status' > "$OUTDIR/nextcloud-status.txt" || true
fi


# 9) Package versions (Fedora/RPM based)
cap "versions" bash -lc 'rpm -qa | egrep -i "(btrfs|podman|traefik|crowdsec|nextcloud|mariadb|redis|wireguard|fail2ban|firewalld)" | sort' > "$OUTDIR/versions.txt" || true


# Bundle
( cd "$OUTDIR"/.. && tar czf "$ARCHIVE" "$(basename "$OUTDIR")" )
echo "\nCreated archive: $PWD/$ARCHIVE"
