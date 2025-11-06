# Git Setup Guide for Homelab Project

**Purpose:** Initialize version control for your homelab configuration and documentation
**Last Updated:** October 25, 2025

---

## Why Use Git for Your Homelab?

**Benefits:**
- Track all configuration changes over time
- Easy rollback if something breaks
- Document what changed and why (commit messages)
- Branch for experimental changes
- Sync with remote backup (GitHub, GitLab, etc.)
- Collaborate and share configurations

---

## Initial Setup

### 1. Install Git (if not already installed)

```bash
# Check if Git is installed
git --version

# Install on Fedora (if needed)
sudo dnf install git
```

### 2. Configure Git Identity

```bash
# Set your name and email
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# Set default branch name to 'main'
git config --global init.defaultBranch main

# Set default editor (optional)
git config --global core.editor nano  # or vim, or code
```

### 3. Initialize Repository

```bash
# Navigate to your containers directory
cd ~/containers

# Initialize Git repository
git init

# Verify initialization
ls -la | grep .git
# You should see: drwxr-xr-x.  7 patriark patriark 4096 Oct 25 12:00 .git
```

---

## Create .gitignore

This file tells Git which files/directories to ignore (never track).

### Create the file

```bash
cd ~/containers
nano .gitignore
```

### Recommended .gitignore content

```
# Secrets - NEVER commit these!
secrets/
**/secrets/
*.key
*.pem
*_token
*_password
*_api_key

# SSL certificates and private keys
letsencrypt/
*/letsencrypt/
acme.json
*/acme.json
*.crt
*.key
*.pem

# Logs
*.log
logs/
*/logs/

# Temporary files
*.tmp
*.temp
*.swp
*.swo
*~
.DS_Store

# Backup files
backups/
*.backup
*.bak
*.old
*.new

# Database files (if large)
*.db
*.sqlite
*.sqlite3

# CrowdSec generated files
config/crowdsec/config.yaml
config/crowdsec/local_api_credentials.yaml
data/crowdsec/

# Container runtime data
data/*/
db/*/

# Editor files
.vscode/
.idea/
*.sublime-*

# System files
.Trash-*/
Desktop.ini
Thumbs.db
```

### Save and test

```bash
# Save the file (Ctrl+X, Y, Enter in nano)

# Test what Git will track
git status
# Should show only files you want to track
```

---

## Initial Commit

### 1. Stage files for commit

```bash
# See what will be committed
git status

# Add specific directories
git add config/
git add docs/
git add scripts/
git add .gitignore

# Or add everything (will respect .gitignore)
git add .

# Review what's staged
git status
```

### 2. Create first commit

```bash
# Commit with descriptive message
git commit -m "Initial commit: homelab configuration and documentation

- Traefik reverse proxy with SSL
- CrowdSec security
- Tinyauth authentication
- Jellyfin media server
- Complete documentation
- Automation scripts"

# View commit
git log
```

---

## Recommended Branching Strategy

### Strategy: Simple Main + Feature Branches

```
main (production)
  ├─ feature/monitoring-stack (for Grafana/Prometheus setup)
  ├─ feature/nextcloud (for Nextcloud deployment)
  └─ feature/2fa (for 2FA implementation)
```

### Creating branches

```bash
# Create and switch to new branch
git checkout -b feature/monitoring-stack

# Make changes, test them
# ...

# Commit changes
git add .
git commit -m "Add Prometheus configuration"

# Switch back to main
git checkout main

# Merge feature if successful
git merge feature/monitoring-stack

# Delete feature branch (optional)
git branch -d feature/monitoring-stack
```

---

## Daily Workflow

### Making Changes

```bash
# 1. Check current status
git status

# 2. Make your changes
# Edit configs, add services, etc.

# 3. See what changed
git diff

# 4. Stage changes
git add config/traefik/dynamic/routers.yml
# Or stage all changes
git add .

# 5. Commit with descriptive message
git commit -m "Add homepage service to Traefik routing"

# 6. View history
git log --oneline
```

### Before Major Changes

```bash
# Create a checkpoint
git commit -am "Checkpoint before upgrading Traefik to v3.3"

# Or create a branch for the change
git checkout -b upgrade/traefik-3.3
# Make changes...
git commit -am "Upgrade Traefik to v3.3"

# If successful, merge back
git checkout main
git merge upgrade/traefik-3.3

# If something breaks, revert
git checkout main
git reset --hard HEAD~1  # Careful with this!
```

---

## Useful Git Commands

### Viewing History

```bash
# View commit history
git log

# Compact view
git log --oneline

# With graph
git log --oneline --graph --all

# See what changed in last commit
git show

# See changes in specific file
git log -p config/traefik/traefik.yml
```

### Checking Status

```bash
# See current status
git status

# See what changed (not staged)
git diff

# See what will be committed (staged)
git diff --staged

# See changed files only
git diff --name-only
```

### Undoing Changes

```bash
# Discard changes in file (BEFORE staging)
git checkout -- config/traefik/traefik.yml

# Unstage file (AFTER git add)
git reset HEAD config/traefik/traefik.yml

# Amend last commit (if not pushed)
git commit --amend -m "New commit message"

# Revert last commit (safe, creates new commit)
git revert HEAD

# Hard reset to previous commit (DESTRUCTIVE!)
git reset --hard HEAD~1
```

### Comparing Versions

```bash
# Compare working directory with last commit
git diff HEAD

# Compare two commits
git diff abc123 def456

# Compare file between commits
git diff abc123:config/traefik/traefik.yml def456:config/traefik/traefik.yml
```

---

## Setting Up Remote Backup

### Option 1: GitHub (Private Repository)

```bash
# 1. Create private repository on GitHub
# Go to github.com, create new repository: "homelab-config" (private)

# 2. Add remote
git remote add origin https://github.com/yourusername/homelab-config.git

# 3. Push to GitHub
git push -u origin main

# 4. Future pushes
git push
```

### Option 2: Self-hosted Gitea/Forgejo

```bash
# 1. Deploy Gitea container (separate guide needed)

# 2. Add remote
git remote add origin https://git.patriark.org/patriark/homelab-config.git

# 3. Push
git push -u origin main
```

### Option 3: Local Backup Only

```bash
# Create bare repository on external drive
cd /mnt/btrfs-pool/subvol7-backups
git clone --bare ~/containers homelab-config.git

# Add as remote
cd ~/containers
git remote add backup /mnt/btrfs-pool/subvol7-backups/homelab-config.git

# Push to backup
git push backup main
```

---

## Automated Backup Script

### Create git-backup.sh

```bash
nano ~/containers/scripts/git-backup.sh
```

### Script content

```bash
#!/bin/bash
# Git backup script for homelab configuration

REPO_DIR="$HOME/containers"
BACKUP_REMOTE="backup"  # or "origin" for GitHub

cd "$REPO_DIR" || exit 1

# Check if there are changes
if [[ -n $(git status -s) ]]; then
    echo "Changes detected, creating automatic backup commit..."
    
    # Add all changes
    git add .
    
    # Commit with timestamp
    git commit -m "Automatic backup: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # Push to remote (if configured)
    if git remote get-url "$BACKUP_REMOTE" &>/dev/null; then
        git push "$BACKUP_REMOTE" main
        echo "Pushed to remote: $BACKUP_REMOTE"
    fi
    
    echo "Backup completed successfully"
else
    echo "No changes detected"
fi
```

### Make executable and test

```bash
chmod +x ~/containers/scripts/git-backup.sh

# Test it
~/containers/scripts/git-backup.sh
```

### Automate with Systemd Timer

```bash
# Create service file
mkdir -p ~/.config/systemd/user/
nano ~/.config/systemd/user/git-backup.service
```

**Service content:**
```ini
[Unit]
Description=Git backup for homelab configuration

[Service]
Type=oneshot
ExecStart=%h/containers/scripts/git-backup.sh
```

```bash
# Create timer file
nano ~/.config/systemd/user/git-backup.timer
```

**Timer content:**
```ini
[Unit]
Description=Git backup timer (daily)

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

**Enable and start:**
```bash
systemctl --user enable --now git-backup.timer

# Check status
systemctl --user status git-backup.timer
systemctl --user list-timers | grep git-backup
```

---

## Best Practices

### 1. Commit Messages

**Good commit messages:**
```
Add Nextcloud service with PostgreSQL backend
Fix Traefik routing for auth.patriark.org
Update CrowdSec to v1.6.0
Improve security headers configuration
```

**Bad commit messages:**
```
Update stuff
Fix
Changes
.
```

**Template for larger changes:**
```
Short summary (50 chars or less)

More detailed explanation if needed. Wrap at 72 characters.
Explain the problem this commit solves and how it solves it.

- Bullet points are okay
- Typically hyphenated or asterisked

Issue references:
- Fixes #123
- Related to monitoring stack deployment
```

### 2. When to Commit

**Commit frequently:**
- After adding a new service
- After fixing a bug
- After updating configuration
- Before making major changes
- After successful testing

**Don't commit:**
- Sensitive information (tokens, passwords)
- Large binary files
- Generated files
- Personal/temporary files

### 3. What to Track

**Do track:**
- Service configurations
- Quadlet files
- Traefik dynamic configs
- Documentation
- Scripts
- README files

**Don't track:**
- Secrets
- SSL certificates
- Database files
- Log files
- Container runtime data
- Backup files

---

## Recovery Scenarios

### Scenario 1: Accidentally Deleted Config File

```bash
# Restore from last commit
git checkout HEAD -- config/traefik/traefik.yml
```

### Scenario 2: Configuration Change Broke Everything

```bash
# See what changed
git diff

# Revert to last working commit
git reset --hard HEAD

# Or revert to specific commit
git log --oneline  # Find commit hash
git reset --hard abc123
```

### Scenario 3: Need to Go Back 5 Commits

```bash
# View history
git log --oneline

# Reset to specific commit (DESTRUCTIVE)
git reset --hard <commit-hash>

# Or create revert commits (SAFE)
git revert HEAD~5..HEAD
```

### Scenario 4: Complete Disaster Recovery

```bash
# If you have remote backup
cd ~/
rm -rf containers  # CAREFUL!
git clone https://github.com/yourusername/homelab-config.git containers

# Or from local backup
git clone /mnt/btrfs-pool/subvol7-backups/homelab-config.git containers
```

---

## Integration with Your Workflow

### 1. Before Making Changes

```bash
# Create a feature branch
git checkout -b feature/add-grafana

# Make changes...
# Test thoroughly...

# Commit
git commit -am "Add Grafana with Prometheus data source"

# Merge if successful
git checkout main
git merge feature/add-grafana
```

### 2. After Successful Deployment

```bash
# Commit the working state
git add .
git commit -m "Successfully deployed Grafana monitoring stack

- Grafana v10.2.0
- Configured Prometheus data source
- Added default dashboards
- Integrated with Traefik auth
- Tested and working"

# Push to backup
git push backup main
```

### 3. During Troubleshooting

```bash
# Save current state before experimenting
git commit -am "Checkpoint before debugging auth issue"

# Try different solutions...
# If solution works:
git commit -am "Fix: Correct Tinyauth APP_URL configuration"

# If solution doesn't work:
git reset --hard HEAD
# Try next solution...
```

---

## Git Aliases (Optional Time-Savers)

```bash
# Add to ~/.gitconfig
git config --global alias.st status
git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.ci commit
git config --global alias.unstage 'reset HEAD --'
git config --global alias.last 'log -1 HEAD'
git config --global alias.lg "log --oneline --graph --all --decorate"

# Now you can use:
git st      # instead of git status
git co main # instead of git checkout main
git lg      # for pretty log view
```

---

## Next Steps

### Immediate
1. ✅ Install Git
2. ✅ Configure identity
3. ✅ Initialize repository
4. ✅ Create .gitignore
5. ✅ Make initial commit

### Short-term
6. ⬜ Set up remote backup (GitHub or local)
7. ⬜ Create git-backup script
8. ⬜ Set up automated daily backups
9. ⬜ Practice basic Git workflow

### Ongoing
10. ⬜ Commit after each significant change
11. ⬜ Use branches for experimental changes
12. ⬜ Write good commit messages
13. ⬜ Regular pushes to remote backup

---

## Learning Resources

**Interactive Tutorial:**
- Learn Git Branching: https://learngitbranching.js.org/

**Documentation:**
- Git Book (free): https://git-scm.com/book/en/v2
- Git Cheat Sheet: https://education.github.com/git-cheat-sheet-education.pdf

**Quick Reference:**
- Git Commands: https://git-scm.com/docs

---

## Troubleshooting

### Problem: "Git not tracking my changes"

**Check:**
```bash
# Is file in .gitignore?
git check-ignore -v filename

# Stage the file
git add filename

# Check status
git status
```

### Problem: "Accidentally committed secrets"

**Solution:**
```bash
# Remove from last commit (NOT PUSHED YET)
git rm --cached secrets/api_token
git commit --amend

# If already pushed - you need to:
# 1. Remove the secret from Git history (complex)
# 2. Rotate the compromised secret immediately
# 3. Consider the secret compromised
```

### Problem: "Merge conflict"

**Solution:**
```bash
# See conflicted files
git status

# Edit files to resolve conflicts
# Look for <<<<<<< ======= >>>>>>> markers

# Stage resolved files
git add filename

# Complete merge
git commit
```

---

**Document Version:** 1.0
**Created:** October 25, 2025
**Purpose:** Git setup and workflow guide for homelab version control
