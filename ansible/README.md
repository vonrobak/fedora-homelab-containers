# Ansible — Pi-hole resolver provisioning (ADR-031)

Config-as-code for the LAN DNS resolver(s): Pi-hole v6 + unbound (DNSSEC) + node_exporter +
keepalived (installed, **not** activated until Phase 3) + log2ram + SSH hardening + nightly backup.

This is the **non-quadlet** half of the homelab's "in Git, reproducible" contract (ADR-031 D3).
It makes node A rebuildable from a dead SD card and lets Phase 3 clone node B as an exact twin.

> **Target is Pi-hole v6** (confirmed Core 6.4.2 / Web 6.5 / FTL 6.6.2, 2026-05-26).
> v5 uses different tooling (setupVars/lighttpd, `pihole -a -t`) — do not run this against a v5 node.

## ⚠️ This touches the LIVE sole resolver — read before running

The Pi at `192.168.1.69` answers DNS for the whole LAN. A bad change = LAN-wide DNS outage.
Mitigations built in: the `unbound` role **validates resolution before** the `pihole` role switches
the upstream to it; all other roles are additive. Still:

1. **Always dry-run first:** `ansible-playbook playbooks/pihole-resolver.yml --check --diff`
2. **Roll out by tag**, additive roles first, resolution-affecting roles last:
   ```
   # additive / low-risk:
   ansible-playbook playbooks/pihole-resolver.yml --tags common,ssh,node_exporter,log2ram,keepalived,backup
   # resolution path (unbound validated, THEN pihole upstream switch):
   ansible-playbook playbooks/pihole-resolver.yml --tags unbound
   ansible-playbook playbooks/pihole-resolver.yml --tags pihole
   ```
3. Keep a second terminal with `dig @192.168.1.69 example.com` running during the resolver-path tags.

## Access (you cannot drive the Pi from a Claude session — FIDO2 touch)

SSH to the Pi uses a passphrase-protected, YubiKey-backed (ED25519-SK) key. Two consequences:
the agent (gcr/Keychain) can't sign SK keys (`IdentityAgent=none`), AND ansible has no TTY to type
the key passphrase (it falls back to the missing `ssh-askpass` → `Permission denied`). The fix is to
**pre-open one master SSH connection by hand** (passphrase + one touch) that ansible then reuses.

- The Pi's SSH user is **`patriark`** (not `pi`).
- `inventory.ini` uses `~/.ssh/id_ed25519_sk_yk5c-li` (the always-connected YubiKey). Its pubkey must
  be in the Pi's `~patriark/.ssh/authorized_keys`.
- If `sudo` on the Pi prompts for a password, add `-K` (`--ask-become-pass`).

```bash
# 1. Open ONE persistent master connection (enter passphrase + touch the YubiKey once).
#    ControlPath MUST match ansible.cfg's control_path so ansible reuses this connection.
ssh -F /dev/null -o IdentityAgent=none -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519_sk_yk5c-li \
    -o ControlMaster=auto -o ControlPersist=1800s -o ControlPath=~/.ssh/ansible-cm-%h-%p-%r \
    -fN patriark@192.168.1.69
ssh -O check -o ControlPath=~/.ssh/ansible-cm-%h-%p-%r patriark@192.168.1.69   # "Master running"

# 2. Now ansible reuses the master — no per-task auth, no passphrase prompt.
cd ~/containers/ansible
ansible -m ping resolvers                                      # "pong"
ansible-playbook playbooks/pihole-resolver.yml --check --diff  # dry run
```

If the master expires (30 min idle), just re-run step 1. To close it early:
`ssh -O exit -o ControlPath=~/.ssh/ansible-cm-%h-%p-%r patriark@192.168.1.69`.

## Secrets

Phase 1 needs none in Git. Phase 3's keepalived VRRP `auth_pass` is a secret — supply it via
`ansible-vault` (e.g. `group_vars/resolvers/vault.yml`), never commit it. The placeholder in
`keepalived.conf.j2` is inert because the service is stopped in Phase 1.

## D8 backup — one manual step after the first run

The `pihole_backup` role generates a passwordless rsync key **on the Pi** and prints its public key.
The Pi *pushes* nightly (a cron/timer can't do a FIDO2 touch to pull). On the backup host
(`fedora-htpc`) install the `rrsync` binary, then authorize that pubkey **restricted** to the dir:

```bash
sudo dnf install -y rsync-rrsync     # provides /usr/bin/rrsync
# append to ~patriark/.ssh/authorized_keys (absolute rrsync path — forced commands get a minimal PATH):
from="192.168.1.69",command="/usr/bin/rrsync -wo /home/patriark/containers/data/pihole-backups/raspberrypi",no-agent-forwarding,no-port-forwarding,no-pty,no-X11-forwarding <PASTE pihole-backup pubkey>
```

The target dir already lives in Urd's `htpc-home` backup set (priority 1, both drives), so each
nightly export is snapshotted with retention automatically. The timer fires at 03:30, before Urd's
04:00 run, so the fresh export is captured the same night.

## Layout

```
ansible.cfg              defaults (ControlMaster = one touch per run)
inventory.ini            resolvers group; node A = raspberrypi (192.168.1.69)
group_vars/resolvers.yml sanitised settings (committed)
host_vars/raspberrypi.yml node-A specifics (keepalived MASTER/priority)
playbooks/pihole-resolver.yml  main play (roles + tags)
roles/  common ssh_hardening unbound pihole node_exporter log2ram keepalived pihole_backup
```
