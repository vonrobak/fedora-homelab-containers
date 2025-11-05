# Git Workflow Guide

## Setup Checklist

### 1. SSH Key Setup (One-time)
```bash
# Generate Ed25519 SSH key if you haven't already
ssh-keygen -t ed25519 -C "your.email@example.com" -f ~/.ssh/id_ed25519

# Add to SSH agent (macOS)
ssh-add --apple-use-keychain ~/.ssh/id_ed25519

# Copy public key to GitHub
cat ~/.ssh/id_ed25519.pub | pbcopy
# Then add it at https://github.com/settings/ssh/new
```

### 2. GPG Signing Setup (One-time, Optional but Recommended)
```bash
# List existing keys
gpg --list-secret-keys

# Or generate a new key
gpg --full-generate-key
# Select: 1) RSA and RSA, 2) 4096 bits, 3) expiration as needed

# Configure Git with your GPG key ID
git config --global user.signingkey YOUR_GPG_KEY_ID
```

### 3. Verify Remote Uses SSH
```bash
cd fedora-homelab-containers
git remote set-url origin git@github.com:vonrobak/fedora-homelab-containers.git
git remote -v
```

## Daily Workflow

### Creating a Feature Branch
```bash
# Update main first
git fetch origin
git checkout main
git pull origin main

# Create feature branch
git checkout -b feature/description-of-change
```

### Making Commits
```bash
# Stage changes
git add file1 file2

# Commit with GPG signing (automatic with config)
git commit -m "Clear, descriptive commit message"

# View commits
git log --oneline -5
```

### Pushing Changes
```bash
# Push branch to GitHub
git push -u origin feature/description-of-change

# Later pushes on same branch
git push
```

### Creating Pull Requests
1. Go to https://github.com/vonrobak/fedora-homelab-containers
2. Create PR from your feature branch to `main`
3. Add description and testing notes
4. Request review if needed

### Merging Strategy
- Use "Squash and merge" for clean history on small changes
- Use "Create a merge commit" for feature branches
- Delete branch after merge

## Branch Naming Conventions

- **Features**: `feature/short-description`
- **Bugfixes**: `bugfix/short-description`
- **Documentation**: `docs/short-description`
- **Hotfixes**: `hotfix/short-description`

## Important Practices

### ✅ Do's
- Pull before starting work: `git pull origin main`
- Use descriptive commit messages
- Keep commits focused (one concern per commit)
- Review your own changes before pushing
- Use feature branches for all work

### ❌ Don'ts
- Don't commit sensitive data (secrets, passwords, API keys)
- Don't force push to main: `git push --force`
- Don't make large commits without review
- Don't skip testing before pushing
- Don't commit `.env` files or credentials

## Useful Commands

```bash
# Check status
git status

# View changes before committing
git diff

# Undo last commit (keep changes)
git reset --soft HEAD~1

# View history
git log --oneline --graph --all

# Stash work temporarily
git stash
git stash pop

# Sync fork with upstream (if applicable)
git fetch upstream
git rebase upstream/main
```

## Security Configuration Summary

Your Git is configured with:
- ✅ SSH authentication (Ed25519 keys)
- ✅ GPG commit signing enabled
- ✅ Strict host key checking (prevents MITM attacks)
- ✅ Automatic pruning of deleted remote branches
- ✅ Rebase-based pulls (cleaner history)
- ✅ Simple push strategy (only current branch)

## Next Steps

1. Verify SSH connection: `ssh -T git@github.com`
2. Set up GPG key if not done: See section 2 above
3. Start working on your first branch following the daily workflow
