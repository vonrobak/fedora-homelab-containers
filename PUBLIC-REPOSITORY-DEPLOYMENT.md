# Public Repository & Portfolio Website Deployment Guide

**Purpose:** Step-by-step guide to create public GitHub repository and deploy portfolio website using GitHub Pages.

**Status:** Ready to execute
**Estimated Time:** 1-2 hours

---

## Overview

This guide walks through:
1. Creating sanitized copy of repository
2. Setting up new public GitHub repository
3. Deploying portfolio website via GitHub Pages
4. Ongoing maintenance strategy

---

## Prerequisites

- [x] Private homelab repository complete
- [x] Sanitization script created (`scripts/sanitize-for-public.sh`)
- [x] Public README created (`README-PUBLIC.md`)
- [x] GitHub Pages configuration created (`docs/_config.yml`, `docs/index.md`)
- [ ] GitHub account (public repository access)
- [ ] Git configured on local machine

---

## Part 1: Create Sanitized Copy

### Step 1: Clone Repository to New Directory

```bash
# Navigate to parent directory
cd ~/

# Clone private repo to new directory
git clone ~/fedora-homelab-containers homelab-public

# Enter new directory
cd homelab-public
```

### Step 2: Remove Private Git History

```bash
# Remove connection to private repository
git remote remove origin

# Check remotes (should be empty)
git remote -v
```

### Step 3: Run Sanitization Script

```bash
# Make script executable (if not already)
chmod +x scripts/sanitize-for-public.sh

# Run sanitization
./scripts/sanitize-for-public.sh
```

**Script will:**
- Create backup in `sanitization-backup-TIMESTAMP/`
- Replace `patriark.org` with `example.com`
- Replace local IPs with generic addresses
- Replace email with `admin@example.com`
- Replace username with `homelab-admin`
- Verify no sensitive data remains

**Expected output:**
```
🔒 Homelab Repository Sanitization
==========================================

⚠️  WARNING: This will modify files in place!
Make sure you're working on a copy or branch, not your main repository.

Continue with sanitization? (yes/no): yes

Starting sanitization...

📦 Creating backup in sanitization-backup-20251111-...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Domain Sanitization
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 Replacing: patriark.org → example.com
  ✓ Replaced 247 occurrences
...

✅ Sanitization Complete!
```

### Step 4: Replace README with Public Version

```bash
# Replace root README with public version
mv README.md README-PRIVATE.md
mv README-PUBLIC.md README.md
```

### Step 5: Review Changes

```bash
# Review all changes made
git diff

# Check random files manually
cat CLAUDE.md | grep -i "patriark\|example"
cat docs/PORTFOLIO.md | grep -i "patriark\|example"

# Verify sensitive patterns removed
grep -r "patriark\.org" docs/ --include="*.md" | wc -l  # Should be 0
grep -r "@proton\.me" docs/ --include="*.md" | wc -l   # Should be 0
```

### Step 6: Commit Sanitized Changes

```bash
# Stage all changes
git add -A

# Commit with sanitization message
git commit -m "Sanitize repository for public release

- Replace patriark.org with example.com
- Replace personal email with admin@example.com
- Replace specific IPs with generic addresses
- Add public README.md
- Add LICENSE (MIT)
- Add .github/ enhancements
- Add GitHub Pages configuration"
```

---

## Part 2: Create GitHub Public Repository

### Step 1: Create Repository on GitHub

**Via GitHub Web Interface:**

1. Go to https://github.com/new
2. Fill in details:
   - **Name:** `homelab-infrastructure` (or `homelab-infrastructure-public`)
   - **Description:** "Production-grade self-hosted infrastructure with enterprise-level reliability, security, and observability. Demonstrates DevOps/SRE best practices."
   - **Visibility:** ✅ Public
   - **Initialize:** ❌ No README (we already have one)
   - **Add .gitignore:** ❌ None (already configured)
   - **Choose license:** ❌ None (already have MIT LICENSE)

3. Click "Create repository"

### Step 2: Add Remote and Push

```bash
# Add GitHub repository as remote
git remote add origin https://github.com/YOUR_USERNAME/homelab-infrastructure.git

# Verify remote
git remote -v

# Push to GitHub
git push -u origin main
```

**If using different branch name (e.g., master):**
```bash
git branch -M main
git push -u origin main
```

### Step 3: Configure Repository Settings

**On GitHub:**

1. Navigate to repository Settings
2. **General:**
   - Features: ✅ Issues, ❌ Projects, ❌ Wiki
   - Pull Requests: ❌ Allow merge commits (not accepting PRs)
3. **Topics:** Add tags for discoverability:
   - `homelab`
   - `devops`
   - `sre`
   - `infrastructure`
   - `podman`
   - `containers`
   - `monitoring`
   - `security`
   - `self-hosted`
   - `portfolio`

### Step 4: Update Repository Description

Add website URL once GitHub Pages is deployed (next part).

---

## Part 3: Deploy Portfolio Website (GitHub Pages)

### Step 1: Enable GitHub Pages

**On GitHub:**

1. Go to repository Settings
2. Navigate to "Pages" (left sidebar)
3. Configure:
   - **Source:** Deploy from a branch
   - **Branch:** `main` (or `master`)
   - **Folder:** `/docs`
4. Click "Save"

**GitHub will:**
- Build Jekyll site from `/docs` directory
- Deploy to `https://YOUR_USERNAME.github.io/homelab-infrastructure/`
- Takes 2-5 minutes for first deployment

### Step 2: Wait for Deployment

Check deployment status:
1. Go to repository "Actions" tab
2. Look for "pages build and deployment" workflow
3. Wait for ✅ green checkmark

### Step 3: Verify Website

Visit your portfolio site:
```
https://YOUR_USERNAME.github.io/homelab-infrastructure/
```

**Expected:**
- Landing page with project overview
- Links to Portfolio, Architecture Diagrams, Resume Bullets
- Mermaid diagrams rendering automatically
- Professional layout (Cayman theme)

### Step 4: Test Navigation

Click through:
- [x] Portfolio Document (PORTFOLIO.md)
- [x] Architecture Diagrams (ARCHITECTURE-DIAGRAMS.md)
- [x] Resume Bullets (RESUME-BULLET-POINTS.md)
- [x] Documentation Index (README.md)

**If Mermaid diagrams not rendering:**
- GitHub Pages may need plugin
- Alternative: Use GitHub's automatic rendering (diagrams work in README)

### Step 5: Customize Domain (Optional)

**If you have custom domain:**

1. Add CNAME record in DNS:
   ```
   portfolio.yourdomain.com → YOUR_USERNAME.github.io
   ```

2. In GitHub Pages settings:
   - Custom domain: `portfolio.yourdomain.com`
   - ✅ Enforce HTTPS

---

## Part 4: Update External Links

### Step 1: Update GitHub Repository

Add website link to repository:
1. Edit repository details (About section)
2. Add website: `https://YOUR_USERNAME.github.io/homelab-infrastructure/`
3. Save

### Step 2: Update LinkedIn

Add to Projects or Experience:
- **Title:** "Production-Grade Homelab Infrastructure"
- **Description:** "Enterprise-level self-hosted infrastructure demonstrating DevOps/SRE best practices. 100% health check coverage, phishing-resistant authentication, comprehensive monitoring."
- **Link:** `https://github.com/YOUR_USERNAME/homelab-infrastructure`
- **Website:** `https://YOUR_USERNAME.github.io/homelab-infrastructure/`

### Step 3: Update Resume

Add to Projects section:
- See [RESUME-BULLET-POINTS.md](docs/RESUME-BULLET-POINTS.md) for ready-to-use bullets
- Choose 4-6 bullets that match target role
- Link to GitHub repository and/or portfolio website

---

## Part 5: Verification Checklist

Before considering deployment complete:

### Security Verification

- [ ] No personal domain names (`patriark.org` → `example.com`)
- [ ] No personal emails (`...@proton.me` → `admin@example.com`)
- [ ] No specific local IPs (generic `192.168.1.x` okay)
- [ ] No public IPs (replaced with TEST-NET range)
- [ ] No secrets/API keys (should be gitignored)
- [ ] No personal photos/media references

### Content Verification

- [ ] README.md is professional and accurate
- [ ] LICENSE file present (MIT)
- [ ] CONTRIBUTING.md explains usage
- [ ] Portfolio document showcases achievements
- [ ] Architecture diagrams render correctly
- [ ] Resume bullets are job-ready

### Website Verification

- [ ] GitHub Pages deployed successfully
- [ ] Landing page loads without errors
- [ ] Navigation works (all links functional)
- [ ] Mermaid diagrams render (or documented workaround)
- [ ] Mobile responsive (test on phone)
- [ ] Professional appearance

### Repository Verification

- [ ] Topics/tags added for discoverability
- [ ] Repository description clear and compelling
- [ ] Website link added to About section
- [ ] Issues enabled for questions/discussions
- [ ] PR settings configured (disabled or selective)

---

## Part 6: Ongoing Maintenance

### Keeping Public Repo Updated

**Recommended Approach:** Manual sync (prevents accidental leaks)

**When to update:**
- After major feature additions
- After significant documentation improvements
- Quarterly review and sync

**Update Process:**

1. **In private repo:**
   ```bash
   cd ~/fedora-homelab-containers
   git pull  # Get latest changes
   ```

2. **Create fresh sanitized copy:**
   ```bash
   cd ~/
   rm -rf homelab-public  # Remove old copy
   git clone ~/fedora-homelab-containers homelab-public
   cd homelab-public
   ```

3. **Sanitize and push:**
   ```bash
   ./scripts/sanitize-for-public.sh
   mv README.md README-PRIVATE.md
   mv README-PUBLIC.md README.md
   git remote add origin https://github.com/YOUR_USERNAME/homelab-infrastructure.git
   git add -A
   git commit -m "Update: [description of changes]"
   git push origin main
   ```

**GitHub Pages auto-rebuilds** on push (2-5 minutes).

### What to Sync

**Do sync:**
- New ADRs (architecture decisions)
- Updated service guides
- New troubleshooting insights
- Architecture diagram improvements
- Portfolio document updates

**Don't sync:**
- Personal configuration files
- Real domain/IP updates
- Sensitive operational details
- Private deployment notes

---

## Troubleshooting

### Issue: GitHub Pages Not Building

**Symptoms:** No site at expected URL

**Solutions:**
1. Check Actions tab for build errors
2. Verify `/docs` folder exists in repository
3. Ensure `_config.yml` is valid YAML
4. Check Pages settings (correct branch/folder)

### Issue: Mermaid Diagrams Not Rendering

**Symptoms:** Diagrams show as code blocks

**Solutions:**
1. GitHub's markdown renderer supports Mermaid (should work in README)
2. Jekyll on GitHub Pages may need plugin
3. Alternative: Add to `_config.yml`:
   ```yaml
   plugins:
     - jekyll-mermaid
   ```
4. Or use images: export diagrams as PNG/SVG

### Issue: Links Broken on GitHub Pages

**Symptoms:** 404 errors when clicking links

**Solutions:**
1. Use relative links: `[link](../path/file.md)` NOT `/path/file.md`
2. Check `baseurl` in `_config.yml`
3. Test locally: `bundle exec jekyll serve --baseurl /homelab-infrastructure`

### Issue: Sensitive Data Accidentally Pushed

**CRITICAL - Act Fast:**

1. **Delete repository immediately** (Settings → Danger Zone → Delete)
2. **Don't just remove file** - it's in Git history
3. **Create new repository** - don't reuse name
4. **Review sanitization** - what was missed?
5. **Re-sanitize and re-push** with corrections

**Note:** Once public, assume data can be archived forever (Wayback Machine, etc.)

---

## Success Criteria

Repository is ready when:

- ✅ GitHub public repository created and populated
- ✅ No sensitive information in repository
- ✅ GitHub Pages website deployed and accessible
- ✅ All navigation links functional
- ✅ Professional appearance
- ✅ Added to LinkedIn and resume
- ✅ Shareable with potential employers

---

## Next Steps After Deployment

### Immediate (First Week)

1. **Share on LinkedIn:**
   - Post about completing the project
   - Link to GitHub repository
   - Highlight key achievements (100% coverage, YubiKey auth, etc.)

2. **Add to Resume:**
   - Use bullets from RESUME-BULLET-POINTS.md
   - Link to repository and portfolio site

3. **Test Sharing:**
   - Send link to friend/mentor for feedback
   - Check appearance on different devices
   - Verify all content accessible

### Short-Term (First Month)

4. **Job Applications:**
   - Include GitHub link in applications
   - Reference in cover letters
   - Prepare to walk through in interviews

5. **Monitor Analytics** (if added Google Analytics):
   - Track visitors
   - See which pages are popular
   - Adjust based on engagement

6. **Iterate Based on Feedback:**
   - Update based on recruiter questions
   - Add clarifications where needed
   - Keep portfolio document current

---

## Templates for Sharing

### LinkedIn Post Template

```
🚀 Excited to share my latest project: A production-grade homelab infrastructure!

Over the past few months, I built a self-hosted infrastructure platform demonstrating enterprise DevOps/SRE practices:

✅ 100% service reliability coverage
✅ Phishing-resistant auth (YubiKey/WebAuthn)
✅ Comprehensive observability (Prometheus/Grafana/Loki)
✅ AI-driven proactive monitoring

Key technical implementations:
• 16 containerized services (Podman + systemd)
• Layered security (IP reputation → rate limiting → hardware 2FA)
• 90+ documentation files using ADR methodology
• Real-world problem-solving (1,000+ line troubleshooting journal)

Full portfolio and architecture diagrams:
🔗 https://github.com/YOUR_USERNAME/homelab-infrastructure
🌐 https://YOUR_USERNAME.github.io/homelab-infrastructure/

#DevOps #SRE #Infrastructure #Homelab #CloudNative
```

### Cover Letter Paragraph Template

```
I'm particularly excited about this opportunity because of my recent work building production-grade infrastructure. I designed and deployed a self-hosted platform running 16 containerized services with 100% reliability coverage, phishing-resistant authentication using YubiKey/WebAuthn, and comprehensive observability (Prometheus, Grafana, Loki). The project demonstrates enterprise DevOps/SRE practices including layered security, AI-driven proactive monitoring, and configuration-as-code. I documented the entire implementation using Architecture Decision Record methodology, including a 1,000-line deployment journal showing real troubleshooting and solutions. Full technical details are available at: [GitHub link] and [Portfolio site link].
```

### Email Signature Addition

```
---
[Your Name]
DevOps Engineer | SRE | Infrastructure Specialist

Portfolio: https://YOUR_USERNAME.github.io/homelab-infrastructure/
GitHub: https://github.com/YOUR_USERNAME
LinkedIn: https://linkedin.com/in/yourprofile
```

---

## Maintenance Schedule

### Monthly

- [ ] Check for broken links (use GitHub's built-in checker)
- [ ] Review for outdated information
- [ ] Check GitHub Pages still deploying
- [ ] Monitor GitHub Issues for questions

### Quarterly

- [ ] Sync major updates from private repo
- [ ] Update portfolio document with new achievements
- [ ] Refresh resume bullets if approach evolved
- [ ] Review analytics (if configured)

### Yearly

- [ ] Comprehensive documentation audit
- [ ] Update technology versions mentioned
- [ ] Refresh screenshots if UI changed
- [ ] Review SEO and discoverability

---

## Summary

You now have:
- ✅ Sanitized public repository on GitHub
- ✅ Professional portfolio website via GitHub Pages
- ✅ Job-ready resume materials
- ✅ Shareable architecture diagrams
- ✅ Comprehensive documentation

**Time to start applying for jobs!** 🎯

---

**Questions or Issues?**
- Review troubleshooting section above
- Check GitHub Pages documentation
- Open issue in repository for discussions

**Good luck with your job search!** 🚀
