# Getting Started with Context Framework & Auto-Remediation

**Created:** 2025-11-18
**For:** Self-service homelab management with Claude's memory
**Skill Level:** Intermediate Linux user

---

## What You've Built

You now have two powerful frameworks working together:

1. **Context Framework** - Claude remembers your system
2. **Auto-Remediation** - Automated fixes for common problems

Think of it like this:
- **Context** = Claude's long-term memory of your homelab
- **Remediation** = Claude's ability to fix problems automatically

---

## Quick Start: 5-Minute Tour

### 1. Check Your System Profile

```bash
cd ~/containers/.claude/context

# See your complete system snapshot
cat system-profile.json | jq '.'

# Quick summary
jq '{hostname: .system.hostname, services: .service_count, disk: .hardware.storage.system_ssd.used_percent}' system-profile.json
```

**What you'll see:**
- 20 running services
- 5 networks
- System SSD usage (currently 70%)
- AMD Ryzen 5 5600G with GPU info
- Container runtime details

### 2. Query Your Issue History

```bash
cd scripts

# Show all resolved issues
./query-issues.sh --status resolved

# Show critical issues
./query-issues.sh --severity critical

# Show disk-space related issues
./query-issues.sh --category disk-space
```

**Try this:**
```bash
# See the GPU issue you resolved
./query-issues.sh --category performance | grep -A 10 "ISS-008"
```

### 3. Query Deployment History

```bash
# See how Jellyfin was deployed
./query-deployments.sh --service jellyfin

# See all monitoring stack deployments
./query-deployments.sh --pattern monitoring-stack

# See pattern-based vs manual deployments
./query-deployments.sh --method pattern-based | wc -l
```

### 4. Test Auto-Remediation

```bash
cd ../../remediation/scripts

# Dry-run disk cleanup (safe, shows what would happen)
./apply-remediation.sh --playbook disk-cleanup --dry-run

# You just did this! It correctly said "No action needed" at 70%
```

---

## Common Operations Cheatsheet

### Context Queries

```bash
cd ~/containers/.claude/context/scripts

# Find all disk-space issues
./query-issues.sh --category disk-space

# Find ongoing (unresolved) issues
./query-issues.sh --status ongoing

# Find all high/critical severity issues
./query-issues.sh --severity high

# See deployment details for a service
./query-deployments.sh --service prometheus
./query-deployments.sh --service authelia

# Find all services deployed with a specific pattern
./query-deployments.sh --pattern monitoring-stack
./query-deployments.sh --pattern media-server-stack
```

### Context Updates

```bash
cd ~/containers/.claude/context/scripts

# Regenerate system profile (after adding/removing services)
./generate-system-profile.sh

# Check what changed
git diff system-profile.json

# Rebuild issue history (after documenting new issues)
./populate-issue-history.sh

# Rebuild deployment log (after new deployments)
./build-deployment-log.sh
```

### Auto-Remediation

```bash
cd ~/containers/.claude/remediation/scripts

# Dry-run any playbook (safe preview)
./apply-remediation.sh --playbook disk-cleanup --dry-run
./apply-remediation.sh --playbook service-restart --service prometheus --dry-run

# Execute disk cleanup (when SSD > 75%)
./apply-remediation.sh --playbook disk-cleanup

# Restart a failed service
./apply-remediation.sh --playbook service-restart --service grafana

# Check logs from previous remediation runs
ls -lh ../../data/remediation-logs/
tail -50 ../../data/remediation-logs/disk-cleanup-*.log
```

---

## Hands-On Tutorial: Add a New Issue

Let's practice adding an issue to the context framework.

### Scenario: You just fixed a Grafana dashboard issue

**Step 1: Edit the issue population script**
```bash
cd ~/containers/.claude/context/scripts
nano populate-issue-history.sh
```

**Step 2: Add a new issue at the end (before `generate_json`)**
```bash
# Add after the last add_issue call, before "# Generate JSON"
add_issue "ISS-013" \
    "Grafana dashboard missing after restart" \
    "monitoring" \
    "medium" \
    "2025-11-18" \
    "Grafana lost custom dashboard configuration after container restart, returned to default state" \
    "Resolved: Dashboard configuration was not persisted to volume. Added /config/provisioning/dashboards mount to quadlet" \
    "resolved"
```

**Step 3: Regenerate the issue history**
```bash
./populate-issue-history.sh
```

**Step 4: Verify it was added**
```bash
./query-issues.sh --category monitoring
# Should show ISS-013

# Or check the JSON directly
jq '.issues[] | select(.id == "ISS-013")' ../issue-history.json
```

**Step 5: Commit to git**
```bash
cd ~/containers
git add .claude/context/
git commit -m "Add ISS-013: Grafana dashboard persistence issue"
git push
```

**Now Claude knows about this issue and can reference it in future troubleshooting!**

---

## Hands-On Tutorial: Add a New Deployment

Let's practice recording a deployment.

### Scenario: You deployed Vaultwarden

**Step 1: Edit the deployment log script**
```bash
cd ~/containers/.claude/context/scripts
nano build-deployment-log.sh
```

**Step 2: Add deployment entry (in chronological order)**
```bash
# Add in the appropriate date order
add_deployment "vaultwarden" \
    "2025-11-15" \
    "password-manager" \
    "512M" \
    "systemd-reverse_proxy" \
    "Self-hosted password manager with YubiKey 2FA support" \
    "pattern-based"
```

**Step 3: Regenerate the deployment log**
```bash
./build-deployment-log.sh
```

**Step 4: Verify**
```bash
./query-deployments.sh --service vaultwarden
jq '.deployments[] | select(.service == "vaultwarden")' ../deployment-log.json
```

**Step 5: Commit**
```bash
cd ~/containers
git add .claude/context/
git commit -m "Add deployment log entry for Vaultwarden"
git push
```

---

## Practical Scenarios: When to Use What

### Scenario 1: Disk Space Warning

**What happens:**
```
$ df -h /
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme0n1p3  118G   95G   17G  85% /
```

**What to do:**
```bash
cd ~/containers/.claude/remediation/scripts

# Check what cleanup would do
./apply-remediation.sh --playbook disk-cleanup --dry-run

# Execute cleanup
./apply-remediation.sh --playbook disk-cleanup

# Check history for past disk issues
cd ../../context/scripts
./query-issues.sh --category disk-space
# Reference: ISS-001 shows what worked before
```

### Scenario 2: Service Won't Start

**What happens:**
```
$ systemctl --user status prometheus.service
● prometheus.service - Prometheus Monitoring
   Active: failed (Result: exit-code)
```

**What to do:**
```bash
# Check if this issue happened before
cd ~/containers/.claude/context/scripts
./query-issues.sh --status resolved | grep -i prometheus

# Try smart restart
cd ../../remediation/scripts
./apply-remediation.sh --playbook service-restart --service prometheus

# If that doesn't work, check deployment config
cd ../../context/scripts
./query-deployments.sh --service prometheus
# Shows memory limits, networks, pattern used - helps debug
```

### Scenario 3: Deploying a New Service

**What happens:**
You want to deploy Redis for a new application

**What to do:**
```bash
# Check how you deployed Redis before
cd ~/containers/.claude/context/scripts
./query-deployments.sh --service redis-authelia
./query-deployments.sh --service redis-immich

# Both show:
# - Pattern: cache-service
# - Memory: 256M
# - Network: Depends on service

# Use the same pattern
cd ~/containers/.claude/skills/homelab-deployment/scripts
./deploy-from-pattern.sh \
  --pattern cache-service \
  --service-name redis-myapp \
  --hostname redis-myapp \
  --memory 256M

# Record the deployment
cd ~/containers/.claude/context/scripts
nano build-deployment-log.sh
# Add entry, regenerate, commit
```

### Scenario 4: Understanding System State

**What happens:**
You haven't checked the homelab in a week, want quick status

**What to do:**
```bash
# System overview
cd ~/containers
./scripts/homelab-intel.sh

# Check context for recent issues
cd .claude/context/scripts
./query-issues.sh --status ongoing
./query-issues.sh --status investigating

# Check what's running
cat ../system-profile.json | jq '.services[]'

# Check disk usage trend
cat ../system-profile.json | jq '.hardware.storage'
```

---

## Understanding the Files

### Context Framework Files

```
.claude/context/
├── README.md                    # Framework overview
├── system-profile.json          # Current system state (auto-generated)
├── issue-history.json           # Past problems (auto-generated)
├── deployment-log.json          # Deployment history (auto-generated)
├── preferences.yml              # Your automation preferences (edit directly)
└── scripts/
    ├── generate-system-profile.sh    # Regenerate system snapshot
    ├── populate-issue-history.sh     # Rebuild issue database
    ├── build-deployment-log.sh       # Rebuild deployment database
    ├── query-issues.sh               # Search issues
    └── query-deployments.sh          # Search deployments
```

**What to edit vs what to regenerate:**
- ✏️ **Edit these:** `populate-issue-history.sh`, `build-deployment-log.sh`, `preferences.yml`
- 🔄 **Don't edit these:** `system-profile.json`, `issue-history.json`, `deployment-log.json` (auto-generated)
- 📖 **Read-only:** Query scripts just read data

### Remediation Framework Files

```
.claude/remediation/
├── README.md                    # Framework overview
├── playbooks/
│   ├── disk-cleanup.yml         # Disk space remediation
│   ├── service-restart.yml      # Service recovery
│   ├── drift-reconciliation.yml # Config drift fixes (engine pending)
│   └── resource-pressure.yml    # Memory/swap fixes (engine pending)
└── scripts/
    └── apply-remediation.sh     # Execution engine
```

**What's ready to use:**
- ✅ `disk-cleanup` - Fully implemented
- ✅ `service-restart` - Fully implemented
- ⚠️ `drift-reconciliation` - Playbook ready, engine needs implementation
- ⚠️ `resource-pressure` - Playbook ready, engine needs implementation

---

## Maintenance Schedule

### Weekly
```bash
# Update system profile
cd ~/containers/.claude/context/scripts
./generate-system-profile.sh
git diff ../system-profile.json  # Review changes
git commit -am "Weekly system profile update"
git push
```

### After Major Changes
```bash
# After adding/removing services
./generate-system-profile.sh

# After resolving an issue
nano populate-issue-history.sh  # Add the issue
./populate-issue-history.sh

# After deploying a service
nano build-deployment-log.sh  # Add deployment
./build-deployment-log.sh

# Commit all changes
cd ~/containers
git add .claude/context/
git commit -m "Update context: [describe what changed]"
git push
```

### Monthly
```bash
# Check for stale remediation logs
ls -lh ~/containers/data/remediation-logs/
# Logs older than 90 days auto-deleted per preferences.yml

# Review ongoing issues
cd ~/containers/.claude/context/scripts
./query-issues.sh --status ongoing
./query-issues.sh --status investigating
# Update status or resolve as needed
```

---

## Tips & Tricks

### Combining Queries

```bash
cd ~/containers/.claude/context/scripts

# Find all critical issues that are still ongoing
./query-issues.sh --severity critical --status ongoing

# Find all deployments using a specific pattern
./query-deployments.sh --pattern monitoring-stack --method pattern-based
```

### Quick Status Aliases

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# Context shortcuts
alias ctx='cd ~/containers/.claude/context/scripts'
alias ctx-issues='cd ~/containers/.claude/context/scripts && ./query-issues.sh'
alias ctx-deploy='cd ~/containers/.claude/context/scripts && ./query-deployments.sh'
alias ctx-update='cd ~/containers/.claude/context/scripts && ./generate-system-profile.sh'

# Remediation shortcuts
alias remedy='cd ~/containers/.claude/remediation/scripts'
alias remedy-disk='cd ~/containers/.claude/remediation/scripts && ./apply-remediation.sh --playbook disk-cleanup'
alias remedy-dry='cd ~/containers/.claude/remediation/scripts && ./apply-remediation.sh --playbook disk-cleanup --dry-run'

# After adding to bashrc/zshrc:
source ~/.bashrc  # or source ~/.zshrc
```

Then you can use:
```bash
ctx-issues --status ongoing
ctx-deploy --service jellyfin
remedy-dry
```

### JSON Exploration

```bash
cd ~/containers/.claude/context

# Pretty-print entire issue history
jq '.' issue-history.json | less

# Count issues by category
jq '.issues | group_by(.category) | map({category: .[0].category, count: length})' issue-history.json

# Find issues from a specific date
jq '.issues[] | select(.date_encountered == "2025-11-18")' issue-history.json

# Get unique list of all patterns used
jq -r '.deployments[].pattern_used' deployment-log.json | sort -u

# Calculate total memory allocated
jq -r '.deployments[].memory_limit' deployment-log.json | grep -oE '[0-9]+' | awk '{sum+=$1} END {print sum "M total"}'
```

---

## Extending the Framework

### Adding a New Issue Category

**Current categories:** disk-space, deployment, authentication, scripting, monitoring, performance, ssl, media, architecture, operations

**To add a new category (e.g., "networking"):**

1. Edit `populate-issue-history.sh`
2. Add issue with new category:
   ```bash
   add_issue "ISS-XXX" \
       "Network connectivity issue" \
       "networking" \
       ...
   ```
3. Update `.claude/context/README.md` to list the new category
4. Regenerate and commit

### Adding a New Remediation Playbook

**Want to automate a different common issue?**

1. Create new playbook: `.claude/remediation/playbooks/your-playbook.yml`
2. Use `disk-cleanup.yml` as a template
3. Define:
   - Triggers (when it should run)
   - Pre-checks (safety)
   - Actions (what to do)
   - Post-checks (verify success)
4. Test with dry-run
5. Update `apply-remediation.sh` if new playbook needs engine support

---

## Testing Your Knowledge

### Quiz 1: Query Practice

Try to answer these using the query scripts:

1. How many issues are currently ongoing?
2. What pattern was used to deploy Jellyfin?
3. Which services are on the monitoring network?
4. When was the Authelia SSO deployment issue encountered?
5. How much memory is Prometheus allocated?

<details>
<summary>Answers</summary>

```bash
# 1. Ongoing issues
./query-issues.sh --status ongoing | grep -c "\"id\":"

# 2. Jellyfin pattern
./query-deployments.sh --service jellyfin | grep pattern_used

# 3. Services on monitoring network
jq -r '.deployments[] | select(.networks[] | contains("monitoring")) | .service' ../deployment-log.json

# 4. Authelia issue date
./query-issues.sh --category deployment | grep -A 5 "Authelia" | grep date_encountered

# 5. Prometheus memory
./query-deployments.sh --service prometheus | grep memory_limit
```
</details>

### Quiz 2: Troubleshooting Practice

**Scenario:** Your Jellyfin container keeps restarting

**Steps you should take:**
1. Check issue history for similar past problems
2. Check deployment configuration for Jellyfin
3. Look at service logs
4. Try service-restart playbook
5. Check GPU device access (based on ISS-008 history)

<details>
<summary>Commands</summary>

```bash
# 1. Check past issues
cd ~/containers/.claude/context/scripts
./query-issues.sh --category media
./query-issues.sh --category performance

# 2. Check deployment config
./query-deployments.sh --service jellyfin

# 3. Check logs
journalctl --user -u jellyfin.service -n 100

# 4. Try restart playbook
cd ../../remediation/scripts
./apply-remediation.sh --playbook service-restart --service jellyfin --dry-run

# 5. Check GPU access (based on ISS-008)
podman exec jellyfin ls -la /dev/dri/
```
</details>

---

## Getting Help

### When Things Go Wrong

1. **Check the logs:**
   ```bash
   ls -lh ~/containers/data/remediation-logs/
   tail -100 ~/containers/data/remediation-logs/disk-cleanup-*.log
   ```

2. **Dry-run first:**
   ```bash
   ./apply-remediation.sh --playbook <name> --dry-run
   ```

3. **Check preferences:**
   ```bash
   cat ~/containers/.claude/context/preferences.yml
   # Verify settings match your risk tolerance
   ```

4. **Regenerate context if corrupted:**
   ```bash
   cd ~/containers/.claude/context/scripts
   ./generate-system-profile.sh
   ./populate-issue-history.sh
   ./build-deployment-log.sh
   ```

### Understanding Error Messages

**"Playbook not found"**
- Check playbook name spelling
- Verify playbook exists in `.claude/remediation/playbooks/`

**"Dry-run mode - no changes made"**
- This is normal! It means you used `--dry-run` flag
- Remove flag to execute for real

**"Disk usage below threshold"**
- This is good! Remediation not needed
- Script is working correctly (threshold checking)

**"Permission denied"**
- Check file permissions: `ls -la script.sh`
- Make executable: `chmod +x script.sh`

---

## Next Steps

Now that you understand the framework, try:

1. **Practice queries:** Run through the Common Operations Cheatsheet
2. **Add a real issue:** Document a recent problem you solved
3. **Update your profile:** Run `generate-system-profile.sh` weekly
4. **Test remediation:** Run disk-cleanup dry-run to see it in action
5. **Set up aliases:** Add shortcuts to your shell config for faster access

---

## Advanced: Integration with Claude Code

When you work with Claude in the future, you can reference context:

**Example conversation:**
```
You: "I'm seeing high memory usage on Prometheus"

Claude: "Let me check your deployment history...
[reads deployment-log.json]
Your Prometheus is configured with 2G memory limit (deployed 2025-11-06).

Let me also check if you've had memory issues before...
[reads issue-history.json]
ISS-006 shows high swap usage on 2025-11-18. The investigation
suggested reviewing container memory allocations.

Would you like me to:
1. Check current Prometheus memory usage
2. Review your other services' memory allocation
3. Run the resource-pressure remediation playbook"
```

The context framework makes Claude **remember your system** instead of giving generic advice!

---

## Summary

**You now have:**
- ✅ Context Framework (Claude's memory)
- ✅ Auto-Remediation (Claude's automation)
- ✅ Query tools (fast lookups)
- ✅ Safe playbooks (tested and working)

**You can:**
- 📊 Query past issues and deployments
- 🔧 Auto-fix common problems
- 📝 Document new issues/deployments
- 🎯 Get context-aware recommendations

**Keep in mind:**
- Update context after major changes
- Use dry-run before executing remediation
- Document issues as you solve them
- Review preferences.yml periodically

---

**Happy homelabbing! 🚀**

For questions or issues with this framework, check the READMEs:
- `.claude/context/README.md`
- `.claude/remediation/README.md`
