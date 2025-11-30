# Repository Sanitization Guide

**Purpose:** Prepare homelab repository for public release by removing sensitive personal information while maintaining technical value.

---

## Sensitive Information Found

### 1. Domain Names

**Pattern:** `patriark.org` and subdomains
**Occurrences:** ~200+ instances across documentation

**Examples:**
- `grafana.patriark.org`
- `sso.patriark.org`
- `jellyfin.patriark.org`
- `photos.patriark.org`

**Replacement Strategy:** `example.com`
- `grafana.example.com`
- `sso.example.com`
- `jellyfin.example.com`
- `photos.example.com`

### 2. IP Addresses

**Local Network IPs:**
- `192.168.1.x` (home network)
- `192.168.100.x` (Wireguard VPN)

**Public IP:**
- `62.249.184.112` (example from logs)

**Replacement Strategy:**
- Local: `192.168.1.x` → Keep generic (already anonymized) OR use `10.0.0.x`
- Public: Replace with `203.0.113.x` (TEST-NET-3 documentation range)

### 3. Email Addresses

**Pattern:** Personal email
**Occurrences:** Limited (mostly in Authelia user config examples)

**Replacement Strategy:** `admin@example.com`

### 4. Usernames

**Pattern:** `patriark` (username in configs)
**Occurrences:** Throughout documentation and examples

**Replacement Strategy:** `homelab-admin` or `admin`

---

## Files Requiring Sanitization

### High Priority (Contains Domain/IP/Email)

**Documentation:**
- `CLAUDE.md` - Extensive examples with domain
- `docs/PORTFOLIO.md` - Portfolio showcase
- `docs/10-services/guides/authelia.md` - Auth configuration
- `docs/30-security/journal/2025-11-11-authelia-deployment.md` - Deployment journal
- All files in `docs/99-reports/` - System state reports

**Scripts:**
- Review shell scripts for hardcoded domains (likely minimal)

### Medium Priority (May Contain Sensitive Info)

**Configuration Examples:**
- Check any YAML/config file examples in docs
- Quadlet examples in documentation

### Low Priority (Generic Content)

**Architecture docs:**
- Most architecture decision records are generic
- Troubleshooting guides are technical (no personal info)

---

## Sanitization Strategy

### Approach 1: Fork and Sanitize (Recommended)

**Process:**
1. Create sanitization script (search and replace)
2. Test on branch first
3. Create new public repository
4. Push sanitized content

**Pros:**
- Clean separation (private homelab vs public showcase)
- Keep private repo with real domains for operations
- Public repo becomes portfolio piece

**Cons:**
- Maintain two repositories
- Updates need manual sync

### Approach 2: Branch-Based

**Process:**
1. Create `public` branch
2. Sanitize content on public branch
3. Keep `main` branch private with real info

**Pros:**
- Single repository
- Git history preserved

**Cons:**
- Risk of accidentally pushing sensitive info
- More complex to maintain

---

## Recommended Approach: Create Public Fork

### Step 1: Create Sanitization Script

```bash
#!/bin/bash
# sanitize-for-public.sh

# Domain replacements
find . -type f \( -name "*.md" -o -name "*.yml" -o -name "*.yaml" \) \
  -exec sed -i 's/patriark\.org/example.com/g' {} +

# Username replacements
find . -type f \( -name "*.md" -o -name "*.yml" -o -name "*.yaml" \) \
  -exec sed -i 's/patriark/homelab-admin/g' {} +

# Email replacements
find . -type f \( -name "*.md" -o -name "*.yml" -o -name "*.yaml" \) \
  -exec sed -i 's/surfaceideology@proton\.me/admin@example.com/g' {} +

# Public IP replacements
find . -type f \( -name "*.md" -o -name "*.yml" -o -name "*.yaml" \) \
  -exec sed -i 's/62\.249\.184\.112/203.0.113.100/g' {} +

echo "✅ Sanitization complete"
```

### Step 2: Create New Public Repository

**On GitHub:**
1. Create new repository: `homelab-infrastructure-public`
2. Description: "Production-grade self-hosted infrastructure with enterprise-level reliability, security, and observability"
3. Public visibility
4. Add LICENSE (MIT or Apache 2.0)

### Step 3: Push Sanitized Content

```bash
# Clone private repo to new directory
git clone /path/to/current/repo homelab-public
cd homelab-public

# Remove origin (don't push to private repo)
git remote remove origin

# Run sanitization
./sanitize-for-public.sh

# Review changes
git diff

# Add new public remote
git remote add origin https://github.com/YOUR_USERNAME/homelab-infrastructure-public.git

# Push to public repo
git push -u origin main
```

---

## What to Include in Public Repo

### Include (Technical Value)

✅ **Documentation:**
- All ADRs (Architecture Decision Records)
- Service guides (sanitized)
- Troubleshooting journals (sanitized)
- Portfolio materials
- Architecture diagrams

✅ **Scripts:**
- Deployment automation
- Intelligence system
- Backup scripts
- Diagnostic tools

✅ **Configuration Examples:**
- Sanitized quadlet examples
- Traefik configuration patterns (no actual routes)
- Generic monitoring configs

✅ **Project Structure:**
- Directory organization
- Documentation methodology
- Git workflow

### Exclude (No Value or Risk)

❌ **Actual Configurations:**
- Real `~/.config/containers/systemd/` files (have real domains)
- Real `config/traefik/` files (have real API keys potential)
- User databases (even gitignored, don't include)

❌ **Secrets/Keys:**
- Already gitignored (double-check)
- acme.json (Let's Encrypt certificates)
- Any .env files

❌ **Personal Data:**
- Backup logs with real filenames
- System snapshots with real data
- Personal photos/media references

---

## GitHub Repository Enhancements

### Add to Public Repo

**1. Professional README.md**
```markdown
# Production-Grade Homelab Infrastructure

Enterprise-level self-hosted infrastructure demonstrating DevOps/SRE best practices.

[Brief overview, tech stack, key features]
```

**2. LICENSE File**
- MIT License (permissive, portfolio-friendly)
- OR Apache 2.0 (more explicit patent protection)

**3. .github/ Directory**
- `CONTRIBUTING.md` - How to use this as learning resource
- Issue templates (optional)
- PR templates (optional)

**4. Topics/Tags**
- homelab, devops, sre, infrastructure, podman, containers, monitoring, security, self-hosted

---

## Verification Checklist

Before making repository public:

- [ ] Run sanitization script
- [ ] Manually review 10-20 random files for missed sensitive info
- [ ] Check all `.gitignore` entries are present
- [ ] Verify no secrets in Git history: `git log --all --full-history --source -- "*.key" "*.pem" "*.env"`
- [ ] Test repository locally (clone and browse)
- [ ] Review commit messages for sensitive information
- [ ] Ensure LICENSE file is present
- [ ] README.md is professional and accurate

---

## Maintenance Plan

### Keeping Public Repo Updated

**Option A: Manual Sync**
- Update public repo quarterly with major changes
- Run sanitization script each time
- Cherry-pick commits (don't automate)

**Option B: Scripted Sync**
- Create sync script that sanitizes and pushes
- Run monthly or after significant updates
- Review before pushing

**Recommended:** Manual sync (prevents accidental sensitive data leaks)

---

## Portfolio Website Integration

Once public repository is created:

1. Enable GitHub Pages
2. Set source to `docs/` directory or create `gh-pages` branch
3. Use Jekyll/MkDocs theme
4. Custom domain (optional): `portfolio.example.com`

**Content:**
- PORTFOLIO.md as landing page
- Architecture diagrams render automatically (Mermaid)
- Link to full documentation
- Resume bullet points

---

## Next Steps

1. Review this sanitization plan
2. Create sanitization script
3. Test on branch first
4. Create new public GitHub repository
5. Push sanitized content
6. Enable GitHub Pages
7. Add repository to resume/LinkedIn

**Timeline:** 1-2 hours for sanitization and initial setup

---

**Security Note:** Once public, assume all content can be archived forever. Double-check before pushing!
