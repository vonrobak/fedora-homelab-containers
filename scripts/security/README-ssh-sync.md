# YubiKey SSH Key Sync — Quick Start

This mini-toolkit distributes a **canonical** `authorized_keys` file (YubiKey-only)
to multiple hosts (e.g., `fedora-htpc.lokal`, `raspberrypi.lokal`) with backups,
correct permissions, and optional verification.

## Files

- `ssh-hosts.env` — configure target hosts, remote user, and path to canonical keys
- `authorized_keys.lan` — example canonical key file (replace with your real keys)
- `sync-ssh-keys.sh` — the sync tool

## Recommended Canonical File

Store your **source of truth** in your repo, e.g.:
`~/containers/docs/30-security/authorized_keys.lan`

Populate it from your verified YubiKey public keys (MacBook source of truth):
```bash
ssh-add -L | grep "sk-" > ~/containers/docs/30-security/authorized_keys.lan
# (Optional) add LAN restriction if not present
sed -i 's/^/from="192.168.1.0\/24" /' ~/containers/docs/30-security/authorized_keys.lan
```

## Configure

Edit `ssh-hosts.env`:
```bash
HOSTS="fedora-htpc.lokal 192.168.1.70 raspberrypi.lokal 192.168.1.69"
REMOTE_USER="patriark"
AUTHORIZED_KEYS_PATH="${HOME}/containers/docs/30-security/authorized_keys.lan"
SSH_PORT="22"
```

## Run

```bash
chmod +x sync-ssh-keys.sh
# Preview
./sync-ssh-keys.sh --dry-run
# Execute and verify
./sync-ssh-keys.sh --verify
# Limit to a subset
./sync-ssh-keys.sh --verify --limit "raspberrypi.lokal"
```

**What it does**
1. Creates `~/.ssh` on remote if missing (700).
2. Backs up existing `authorized_keys` with a timestamp.
3. Uploads your canonical file, sets `600`, moves into place.
4. Optional `--verify`: checks non-interactive key auth.

> Policy tip: keep `from="192.168.1.0/24"` on each key line to enforce LAN-only auth.

## Rollback

Each run creates a backup like:
`~/.ssh/authorized_keys.backup-YYYYmmddHHMMSS` on the remote.
To restore:
```bash
ssh patriark@host "cp ~/.ssh/authorized_keys.backup-<stamp> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

## Troubleshooting

- If `--verify` fails, check on the remote:
  - `/etc/ssh/sshd_config` or `sshd_config.d/*.conf` (PubkeyAuthentication yes, PasswordAuthentication no, etc.).
  - Permissions: `~/.ssh (700)`, `authorized_keys (600)`.
  - Key order on the client (`~/.ssh/config`) so the correct YubiKey is attempted first.
