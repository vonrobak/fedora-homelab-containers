---
name: commit-push-pr
description: Stage changes, commit with GPG signature, push to remote, and create PR with gh CLI
argument-hint: Optional commit message prefix (e.g., "feat", "fix", "docs")
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# Commit, Push, and Create PR

Automated git workflow following homelab conventions:
- GPG-signed commits (auto-configured in git)
- Branch naming: feature/*, fix/*, docs/*
- Structured commit messages with homelab context
- PR descriptions with deployment logs and verification results

## Workflow

### Phase 1: Pre-Compute Git Status (Performance Optimization)

Before any analysis, gather ALL git information in parallel for speed:

```bash
# Run these 4 commands in PARALLEL for speed (~0.5s total vs ~2s sequential)
git status --porcelain
git diff --stat
git log --oneline -5
git branch --show-current
```

**Why parallel?** Boris Cherny's optimization from the Twitter thread - pre-computing git status makes the command run quickly.

### Phase 2: Analyze Changes

Parse the pre-computed status to understand what's changing:

1. **Identify changed files**: Quadlets (*.container), Traefik configs (config/traefik/dynamic/*.yml), docs, scripts
2. **Detect change type**:
   - Service deployment: New/modified *.container files
   - Configuration change: Modified config files, scripts
   - Documentation: Only docs/* changed
   - Mixed: Multiple types
3. **Check for deployment context**:
   - Recent deployment journals in docs/10-services/journal/
   - Issue references in .claude/context/issue-history.json
4. **Check current branch**: Feature branch vs main

### Phase 3: Generate Commit Message

Based on change type, generate structured commit message using homelab patterns:

**For Service Deployment:**
```
<prefix OR "deploy">: <service-name> <description>

- Quadlet configuration (<memory>, <networks>)
- Traefik route with <middleware>
- <Integration details>

Configuration:
  Image: <image>
  Networks: <networks>
  Memory: <memory>

Verification: <verification status from logs if available>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**For Configuration Change:**
```
<prefix OR "fix">: <description>

Changes:
- <file1>: <change summary>
- <file2>: <change summary>

Impact: <service restarts required, affected services>
Verification: <checks performed>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**For Documentation:**
```
docs: <description>

- <list of doc changes>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

### Phase 4: Execute Git Operations

```bash
# 1. Check we're in git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "ERROR: Not a git repository"
  exit 1
fi

# 2. Check for changes
if [[ -z "$(git status --porcelain)" ]]; then
  echo "No changes to commit"
  exit 0
fi

# 3. Check current branch
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" == "main" ]]; then
  echo "⚠️  WARNING: On main branch. Consider creating feature branch first."
  echo "Suggestion: git checkout -b feature/<description>"
  # Ask user if they want to continue or create branch
fi

# 4. Stage changes (detect relevant files from pre-computed status)
git add <relevant files>

# 5. Commit with message (using heredoc from CLAUDE.md pattern)
git commit -m "$(cat <<'EOF'
<generated commit message>
EOF
)"

# Note: GPG signing happens automatically (commit.gpgsign=true in user config)

# 6. Push to remote
if [[ "$CURRENT_BRANCH" == "main" ]]; then
  git push origin main
else
  # Feature branch - push with -u to set upstream
  git push -u origin "$CURRENT_BRANCH"
fi
```

### Phase 5: Create PR with gh CLI

**Check gh authentication:**
```bash
if ! gh auth status > /dev/null 2>&1; then
  echo "ERROR: gh CLI not authenticated. Run: gh auth login"
  exit 1
fi
```

**Generate PR description from commits + context:**

```bash
# Analyze all commits since divergence from main
COMMITS=$(git log main..HEAD --oneline)

# Generate PR description
gh pr create --title "<type>: <summary from commits>" --body "$(cat <<'EOF'
## Summary

<Bullet points from commits, analyzing all changes since branch point>

## Deployment Context

<If service deployment detected:>
- Service: <name>
- Pattern: <pattern used from files>
- Networks: <networks from quadlet>
- Middleware: <security layers from Traefik config>

<Link to deployment journal if exists in docs/10-services/journal/>

## Verification

<Include verification results if found in deployment logs:>
- ✓ Service health: <status>
- ✓ External access: <URL>
- ✓ Monitoring: <Prometheus configured>

## Test Plan

- [ ] Verify service accessible at <URL>
- [ ] Check authentication flow (Authelia → service)
- [ ] Monitor for errors in logs (5 min observation)
- [ ] Validate metrics in Grafana dashboard
- [ ] Test service-specific functionality

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**PR base branch detection:**
- Default to `main` as base (from git status)
- Can be overridden if needed

### Error Handling

Handle common failure scenarios:

1. **Not in git repo**: Clear error message
2. **No changes to commit**: Exit gracefully
3. **On main branch**: Warn user, suggest feature branch
4. **gh not authenticated**: Clear remediation instructions
5. **Commit failed**: Show error, don't proceed to push
6. **Push failed**: Show error, don't proceed to PR
7. **PR creation failed**: Show error with gh output

### Integration with Homelab Context

**Reference deployment logs:**
```bash
# Find deployment journals from today or yesterday
RECENT_JOURNALS=$(find ~/containers/docs/10-services/journal/ \
  -name "$(date +%Y-%m-%d)-*.md" -o \
  -name "$(date -d '1 day ago' +%Y-%m-%d)-*.md" 2>/dev/null)

# Include in PR description if found
for journal in $RECENT_JOURNALS; do
  echo "- Related journal: [$(basename $journal)](../docs/10-services/journal/$(basename $journal))"
done
```

**Reference issue history:**
```bash
# Check for recently resolved issues (last 24 hours)
if [[ -f ~/.claude/context/issue-history.json ]]; then
  RECENT_ISSUES=$(jq -r '.issues[] | select(.resolved_at > "'$(date -d '1 day ago' -Iseconds)'") | "- Resolves: \(.id) - \(.summary)"' \
    ~/.claude/context/issue-history.json 2>/dev/null)

  # Include in commit message or PR description
  if [[ -n "$RECENT_ISSUES" ]]; then
    echo "$RECENT_ISSUES"
  fi
fi
```

## Usage Examples

**Simple workflow (auto-detect everything):**
```
/commit-push-pr
```
Claude will:
1. Analyze changes (parallel git commands)
2. Detect change type (deployment, config, docs)
3. Generate appropriate commit message
4. Stage, commit, push
5. Create PR with context

**With type prefix:**
```
/commit-push-pr feat
```
Uses "feat" prefix in commit message instead of auto-detected type.

**Expected behavior:**
- For service deployment: Commit message includes quadlet details, Traefik config, verification status
- For config change: Lists affected files and impact
- For docs: Simple description of doc changes
- PR includes: Deployment context, verification results, test checklist

## Benefits

1. **Speed**: Pre-computed git status (~0.5s vs ~2s)
2. **Context-aware**: Includes deployment logs, issue references
3. **Consistent**: Follows homelab commit conventions
4. **Complete**: One command from uncommitted changes to PR
5. **Safe**: Checks and error handling at each step

## See Also

- CLAUDE.md: Git workflow conventions
- git-advanced-workflows skill: Complex git operations
- homelab-deployment skill: Deployment patterns referenced in PR descriptions
