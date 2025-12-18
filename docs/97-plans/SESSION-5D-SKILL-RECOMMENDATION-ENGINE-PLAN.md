# Session 5D: Skill Recommendation Engine

**Status**: Ready for Implementation
**Priority**: MEDIUM
**Estimated Effort**: 5-7 hours across 2-3 CLI sessions
**Dependencies**: Session 4 (Context Framework), existing Claude skills
**Branch**: TBD (create `feature/skill-recommendation` during implementation)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Architecture Overview](#architecture-overview)
4. [Core Components](#core-components)
5. [Recommendation Algorithm](#recommendation-algorithm)
6. [Implementation Phases](#implementation-phases)
7. [Integration Points](#integration-points)
8. [Testing Strategy](#testing-strategy)
9. [Success Metrics](#success-metrics)
10. [Future Enhancements](#future-enhancements)

---

## Executive Summary

**What**: Intelligent skill recommendation engine that analyzes user requests and automatically suggests (or invokes) the most appropriate Claude skill(s).

**Why**:
- Users don't know which skills exist or what they do
- Skills are underutilized (great tools, but hidden)
- Manual skill selection is slow and error-prone
- No learning from usage patterns

**How**:
- Build task classifier that categorizes user requests
- Map task categories to appropriate skills
- Score recommendations by confidence
- Auto-invoke high-confidence matches
- Learn from usage patterns over time

**Key Deliverables**:
- `scripts/recommend-skill.sh` - Skill recommendation engine (400 lines)
- `.claude/context/skill-usage.json` - Usage tracking database
- `.claude/context/task-skill-map.json` - Task → Skill mapping rules
- Auto-invocation logic in Claude Code wrapper
- `docs/10-services/guides/skill-recommendation.md` - Usage guide

---

## Problem Statement

### Current State: Hidden Skills

You have **5 powerful Claude skills**, but they're underutilized:

1. **homelab-deployment** - Pattern-based service deployment
2. **homelab-intelligence** - System health analysis + recommendations
3. **systematic-debugging** - Four-phase debugging framework
4. **git-advanced-workflows** - Complex git operations
5. **claude-code-analyzer** - Claude Code usage optimization

**Problems**:

**Problem 1: Discovery**
- Users don't know skills exist
- No visibility into what each skill does
- Must remember skill names to invoke

**Problem 2: Decision Paralysis**
- "Should I use homelab-deployment or just run commands manually?"
- "Is this a debugging task or a deployment task?"
- Uncertainty leads to avoiding skills entirely

**Problem 3: No Learning**
- Same questions get answered manually each time
- No memory of "last time we used systematic-debugging for this"
- Can't improve recommendations over time

---

### Desired State: Intelligent Skill Router

**Example Interaction** (Current):
```
User: "Jellyfin won't start. I see errors in the logs about permissions."

Claude thinks:
- This might be a deployment issue?
- Or maybe a debugging task?
- Should I suggest systematic-debugging skill?
- Or just debug manually?

[Makes arbitrary decision, may not use best skill]
```

**Example Interaction** (Desired):
```
User: "Jellyfin won't start. I see errors in the logs about permissions."

Skill Recommendation Engine analyzes:
- Keywords: "won't start", "errors", "logs"
- Category: DEBUGGING
- Historical data: Last 3 similar issues used systematic-debugging
- Confidence: 95%

Claude (auto-invokes systematic-debugging):
"I'm invoking the systematic-debugging skill to help troubleshoot this issue.

[Systematic-debugging runs its four-phase framework...]
```

**Benefits**:
- ✅ Skills always used when appropriate
- ✅ Consistent problem-solving approach
- ✅ Learning from historical patterns
- ✅ Better user experience (less cognitive load)

---

## Architecture Overview

### Data Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    USER REQUEST                                      │
│  "Jellyfin won't start. I see permission errors in logs."           │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│            TASK CLASSIFIER (scripts/recommend-skill.sh)              │
│                                                                      │
│  1. Extract keywords (won't start, errors, logs, permissions)       │
│  2. Identify intent (DEBUGGING)                                     │
│  3. Detect context clues (service name, error type)                 │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│        TASK-SKILL MAPPING (.claude/context/task-skill-map.json)      │
│                                                                      │
│  {                                                                   │
│    "task_categories": [                                             │
│      {                                                               │
│        "category": "DEBUGGING",                                     │
│        "keywords": ["error", "fail", "won't start", "broken"],      │
│        "skills": [                                                   │
│          {                                                           │
│            "name": "systematic-debugging",                          │
│            "priority": 1,                                           │
│            "conditions": ["has_error_message"]                      │
│          }                                                           │
│        ]                                                             │
│      },                                                              │
│      {                                                               │
│        "category": "DEPLOYMENT",                                    │
│        "keywords": ["deploy", "install", "setup", "new service"],   │
│        "skills": [                                                   │
│          {                                                           │
│            "name": "homelab-deployment",                            │
│            "priority": 1                                            │
│          }                                                           │
│        ]                                                             │
│      }                                                               │
│    ]                                                                 │
│  }                                                                   │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│          HISTORICAL USAGE (.claude/context/skill-usage.json)         │
│                                                                      │
│  {                                                                   │
│    "sessions": [                                                     │
│      {                                                               │
│        "timestamp": "2025-11-10T14:30:00Z",                         │
│        "task_category": "DEBUGGING",                                │
│        "skill_used": "systematic-debugging",                        │
│        "task_keywords": ["jellyfin", "won't start", "logs"],        │
│        "outcome": "success",                                         │
│        "user_satisfaction": "resolved"                              │
│      }                                                               │
│    ]                                                                 │
│  }                                                                   │
│                                                                      │
│  → Boost confidence for similar future tasks                        │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│              RECOMMENDATION SCORER                                   │
│                                                                      │
│  For each candidate skill, calculate score:                         │
│                                                                      │
│  score = (                                                           │
│    keyword_match_weight * 0.4 +                                     │
│    historical_success_weight * 0.3 +                                │
│    priority_weight * 0.2 +                                          │
│    recency_weight * 0.1                                             │
│  )                                                                   │
│                                                                      │
│  Example:                                                            │
│  - systematic-debugging: 0.92 (HIGH confidence)                     │
│  - homelab-intelligence: 0.45 (LOW confidence)                      │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│              AUTO-INVOCATION DECISION                                │
│                                                                      │
│  if confidence >= 0.85:                                             │
│    → Auto-invoke skill (inform user)                                │
│  elif confidence >= 0.60:                                           │
│    → Suggest skill (ask user for confirmation)                      │
│  else:                                                               │
│    → No recommendation (use standard approach)                      │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    INVOKE SKILL                                      │
│  /skill systematic-debugging                                         │
│                                                                      │
│  [Skill executes its logic...]                                      │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│              LOG USAGE (.claude/context/skill-usage.json)            │
│                                                                      │
│  Record:                                                             │
│  - Task category                                                     │
│  - Skill used                                                        │
│  - Outcome (success/failure)                                        │
│  - User feedback (if available)                                     │
│                                                                      │
│  → Improve future recommendations                                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Core Components

### Component 1: Task Classifier

**File**: `scripts/recommend-skill.sh`

**Purpose**: Analyze user request and classify task category.

**Task Categories** (8 total):

1. **DEBUGGING** - Service failures, errors, troubleshooting
2. **DEPLOYMENT** - New service installation, configuration
3. **MONITORING** - Health checks, system analysis, diagnostics
4. **GIT_OPERATIONS** - Complex git workflows, rebasing, conflict resolution
5. **OPTIMIZATION** - Performance tuning, Claude Code usage improvement
6. **CONFIGURATION** - Service config changes, updates
7. **QUESTION** - Information requests, "how do I...", "what is..."
8. **UNKNOWN** - Can't classify confidently

**Implementation** (400 lines):
```bash
#!/bin/bash
# scripts/recommend-skill.sh

set -euo pipefail

CONTEXT_DIR="$HOME/.claude/context"
TASK_SKILL_MAP="$CONTEXT_DIR/task-skill-map.json"
SKILL_USAGE="$CONTEXT_DIR/skill-usage.json"

# Initialize files if not exist
init_files() {
    [[ ! -f "$TASK_SKILL_MAP" ]] && create_default_task_skill_map
    [[ ! -f "$SKILL_USAGE" ]] && echo '{"sessions": []}' > "$SKILL_USAGE"
}

# Extract keywords from user request
extract_keywords() {
    local request="$1"

    # Convert to lowercase, remove punctuation, extract meaningful words
    echo "$request" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9 ]/ /g' \
        | tr -s ' ' '\n' \
        | grep -vE '^(a|an|the|is|are|was|were|be|been|being|have|has|had|do|does|did|will|would|should|could|may|might|can)$' \
        | sort | uniq
}

# Classify task based on keywords
classify_task() {
    local keywords="$1"

    # Load task categories
    local categories=$(jq -r '.task_categories[] | @json' "$TASK_SKILL_MAP")

    local best_category=""
    local best_score=0

    while IFS= read -r category_json; do
        local category=$(echo "$category_json" | jq -r '.category')
        local category_keywords=$(echo "$category_json" | jq -r '.keywords[]')

        # Count keyword matches
        local matches=0
        while IFS= read -r kw; do
            if echo "$keywords" | grep -qw "$kw"; then
                ((matches++)) || true
            fi
        done <<< "$category_keywords"

        # Calculate score (normalized by category keyword count)
        local total_keywords=$(echo "$category_keywords" | wc -l)
        local score=$(awk "BEGIN {print $matches / $total_keywords}")

        if (( $(awk "BEGIN {print ($score > $best_score)}") )); then
            best_score=$score
            best_category=$category
        fi
    done <<< "$categories"

    # Require minimum 20% match
    if (( $(awk "BEGIN {print ($best_score < 0.2)}") )); then
        echo "UNKNOWN"
    else
        echo "$best_category"
    fi
}

# Get skill recommendations for category
get_skill_recommendations() {
    local category="$1"
    local keywords="$2"

    # Get skills for this category
    local skills=$(jq -r \
        --arg cat "$category" \
        '.task_categories[] | select(.category == $cat) | .skills[] | @json' \
        "$TASK_SKILL_MAP")

    if [[ -z "$skills" ]]; then
        echo "[]"
        return
    fi

    # Score each skill
    local recommendations="[]"

    while IFS= read -r skill_json; do
        local skill_name=$(echo "$skill_json" | jq -r '.name')
        local priority=$(echo "$skill_json" | jq -r '.priority')

        # Calculate confidence score
        local keyword_score=$(calculate_keyword_score "$keywords" "$skill_name")
        local historical_score=$(calculate_historical_score "$category" "$skill_name")
        local priority_score=$(awk "BEGIN {print 1.0 / $priority}")

        local total_score=$(awk "BEGIN {print ($keyword_score * 0.4) + ($historical_score * 0.3) + ($priority_score * 0.3)}")

        # Add to recommendations
        recommendations=$(echo "$recommendations" | jq \
            --arg name "$skill_name" \
            --argjson score "$total_score" \
            '. += [{name: $name, confidence: $score}]')
    done <<< "$skills"

    # Sort by confidence descending
    echo "$recommendations" | jq 'sort_by(.confidence) | reverse'
}

# Calculate keyword relevance score
calculate_keyword_score() {
    local keywords="$1"
    local skill_name="$2"

    # Get skill-specific keywords from skill metadata
    # For now, use simple heuristics:
    case "$skill_name" in
        homelab-deployment)
            echo "$keywords" | grep -qE '(deploy|install|setup|new)' && echo "1.0" || echo "0.5"
            ;;
        systematic-debugging)
            echo "$keywords" | grep -qE '(error|fail|broken|debug|troubleshoot)' && echo "1.0" || echo "0.5"
            ;;
        homelab-intelligence)
            echo "$keywords" | grep -qE '(health|status|check|analyze|recommend)' && echo "1.0" || echo "0.5"
            ;;
        git-advanced-workflows)
            echo "$keywords" | grep -qE '(git|rebase|merge|conflict|cherry-pick)' && echo "1.0" || echo "0.5"
            ;;
        claude-code-analyzer)
            echo "$keywords" | grep -qE '(optimize|usage|claude|workflow|improve)' && echo "1.0" || echo "0.5"
            ;;
        *)
            echo "0.5"
            ;;
    esac
}

# Calculate historical success score
calculate_historical_score() {
    local category="$1"
    local skill_name="$2"

    # Count successful uses of this skill for this category
    local total_uses=$(jq -r \
        --arg cat "$category" \
        --arg skill "$skill_name" \
        '.sessions | map(select(.task_category == $cat and .skill_used == $skill)) | length' \
        "$SKILL_USAGE")

    local successful_uses=$(jq -r \
        --arg cat "$category" \
        --arg skill "$skill_name" \
        '.sessions | map(select(.task_category == $cat and .skill_used == $skill and .outcome == "success")) | length' \
        "$SKILL_USAGE")

    if (( total_uses == 0 )); then
        echo "0.5"  # Neutral score (no data)
    else
        awk "BEGIN {print $successful_uses / $total_uses}"
    fi
}

# Determine invocation strategy
determine_invocation() {
    local confidence="$1"

    if (( $(awk "BEGIN {print ($confidence >= 0.85)}") )); then
        echo "auto"
    elif (( $(awk "BEGIN {print ($confidence >= 0.60)}") )); then
        echo "suggest"
    else
        echo "none"
    fi
}

# Log skill usage
log_usage() {
    local category="$1"
    local skill="$2"
    local keywords="$3"
    local outcome="${4:-unknown}"

    local entry=$(cat <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "task_category": "$category",
  "skill_used": "$skill",
  "task_keywords": $(echo "$keywords" | jq -R -s -c 'split("\n") | map(select(length > 0))'),
  "outcome": "$outcome"
}
EOF
)

    # Append to skill-usage.json
    local updated=$(jq ".sessions += [$entry]" "$SKILL_USAGE")
    echo "$updated" > "$SKILL_USAGE"
}

# Main
main() {
    local user_request="$*"

    if [[ -z "$user_request" ]]; then
        echo "Usage: $0 <user request>"
        exit 1
    fi

    init_files

    # 1. Extract keywords
    local keywords=$(extract_keywords "$user_request")

    # 2. Classify task
    local category=$(classify_task "$keywords")

    # 3. Get recommendations
    local recommendations=$(get_skill_recommendations "$category" "$keywords")

    # 4. Output
    if [[ "$recommendations" == "[]" ]]; then
        echo "No skill recommendations for this task."
        exit 0
    fi

    # Top recommendation
    local top_skill=$(echo "$recommendations" | jq -r '.[0].name')
    local top_confidence=$(echo "$recommendations" | jq -r '.[0].confidence')
    local invocation=$(determine_invocation "$top_confidence")

    # Format output
    cat <<EOF
Task Category: $category
Recommended Skill: $top_skill (confidence: $(printf "%.0f%%" $(awk "BEGIN {print $top_confidence * 100}")))
Invocation: $invocation

All Recommendations:
$(echo "$recommendations" | jq -r '.[] | "\(.name): \(.confidence * 100 | floor)%"' | nl)

EOF

    # If auto-invoke, return skill name for wrapper to invoke
    if [[ "$invocation" == "auto" ]]; then
        echo "AUTO_INVOKE:$top_skill"
    fi
}

main "$@"
```

---

### Component 2: Task-Skill Mapping Database

**File**: `.claude/context/task-skill-map.json`

**Purpose**: Define which skills are appropriate for which task categories.

**Structure**:
```json
{
  "task_categories": [
    {
      "category": "DEBUGGING",
      "description": "Service failures, errors, troubleshooting",
      "keywords": [
        "error", "fail", "failure", "broken", "crash", "won't start",
        "not working", "debug", "troubleshoot", "logs", "exception",
        "permission denied", "connection refused", "timeout"
      ],
      "skills": [
        {
          "name": "systematic-debugging",
          "priority": 1,
          "conditions": ["has_error_message"],
          "description": "Four-phase debugging framework"
        },
        {
          "name": "homelab-intelligence",
          "priority": 2,
          "conditions": [],
          "description": "System health analysis and recommendations"
        }
      ]
    },
    {
      "category": "DEPLOYMENT",
      "description": "New service installation, configuration",
      "keywords": [
        "deploy", "install", "setup", "configure", "new service",
        "add", "create", "provision", "spin up", "docker", "podman",
        "container", "image"
      ],
      "skills": [
        {
          "name": "homelab-deployment",
          "priority": 1,
          "conditions": [],
          "description": "Pattern-based service deployment with validation"
        }
      ]
    },
    {
      "category": "MONITORING",
      "description": "Health checks, system analysis, diagnostics",
      "keywords": [
        "health", "status", "check", "analyze", "diagnose", "monitor",
        "metrics", "performance", "usage", "report", "dashboard",
        "inspect", "audit"
      ],
      "skills": [
        {
          "name": "homelab-intelligence",
          "priority": 1,
          "conditions": [],
          "description": "Comprehensive system health analysis with scoring"
        }
      ]
    },
    {
      "category": "GIT_OPERATIONS",
      "description": "Complex git workflows, conflict resolution",
      "keywords": [
        "git", "rebase", "merge", "conflict", "cherry-pick", "bisect",
        "worktree", "reflog", "branch", "commit", "reset", "revert",
        "stash"
      ],
      "skills": [
        {
          "name": "git-advanced-workflows",
          "priority": 1,
          "conditions": ["git_operation"],
          "description": "Advanced git operations with safety checks"
        }
      ]
    },
    {
      "category": "OPTIMIZATION",
      "description": "Performance tuning, workflow improvement",
      "keywords": [
        "optimize", "improve", "faster", "slow", "performance",
        "efficiency", "workflow", "claude code", "usage", "better",
        "tune", "speed up"
      ],
      "skills": [
        {
          "name": "claude-code-analyzer",
          "priority": 1,
          "conditions": ["claude_code_related"],
          "description": "Analyze Claude Code usage and provide recommendations"
        },
        {
          "name": "homelab-intelligence",
          "priority": 2,
          "conditions": [],
          "description": "System performance analysis"
        }
      ]
    },
    {
      "category": "CONFIGURATION",
      "description": "Service configuration changes, updates",
      "keywords": [
        "config", "configuration", "setting", "update", "change",
        "modify", "edit", "parameter", "environment", "variable",
        "tuning"
      ],
      "skills": [
        {
          "name": "homelab-deployment",
          "priority": 1,
          "conditions": ["existing_service"],
          "description": "Reconfigure existing service (drift reconciliation)"
        },
        {
          "name": "homelab-intelligence",
          "priority": 2,
          "conditions": [],
          "description": "Validate configuration changes"
        }
      ]
    },
    {
      "category": "QUESTION",
      "description": "Information requests, how-to questions",
      "keywords": [
        "how", "what", "why", "when", "where", "explain", "show",
        "tell", "describe", "documentation", "guide", "help",
        "tutorial"
      ],
      "skills": [
        {
          "name": "homelab-intelligence",
          "priority": 1,
          "conditions": [],
          "description": "Query system state and provide information"
        }
      ]
    },
    {
      "category": "BACKUP_RESTORE",
      "description": "Backup operations, disaster recovery",
      "keywords": [
        "backup", "restore", "snapshot", "recovery", "disaster",
        "btrfs", "data loss", "corruption"
      ],
      "skills": []
    }
  ]
}
```

---

### Component 3: Skill Usage Tracker

**File**: `.claude/context/skill-usage.json`

**Purpose**: Log skill invocations to learn from patterns.

**Structure**:
```json
{
  "sessions": [
    {
      "timestamp": "2025-11-10T14:30:00Z",
      "task_category": "DEBUGGING",
      "skill_used": "systematic-debugging",
      "task_keywords": ["jellyfin", "won't", "start", "permission", "error"],
      "outcome": "success",
      "user_satisfaction": "resolved",
      "notes": "SELinux context issue - resolved with :Z label"
    },
    {
      "timestamp": "2025-11-11T09:15:00Z",
      "task_category": "DEPLOYMENT",
      "skill_used": "homelab-deployment",
      "task_keywords": ["deploy", "immich", "photos"],
      "outcome": "success",
      "user_satisfaction": "satisfied"
    },
    {
      "timestamp": "2025-11-12T16:45:00Z",
      "task_category": "MONITORING",
      "skill_used": "homelab-intelligence",
      "task_keywords": ["health", "check", "system"],
      "outcome": "success",
      "user_satisfaction": "satisfied"
    }
  ],
  "statistics": {
    "total_invocations": 127,
    "by_skill": {
      "homelab-intelligence": 45,
      "homelab-deployment": 38,
      "systematic-debugging": 32,
      "git-advanced-workflows": 8,
      "claude-code-analyzer": 4
    },
    "by_category": {
      "DEBUGGING": 32,
      "DEPLOYMENT": 38,
      "MONITORING": 45,
      "GIT_OPERATIONS": 8,
      "OPTIMIZATION": 4
    },
    "success_rate": 0.94
  }
}
```

**Update Frequency**: After each skill invocation

**Retention**: Keep last 100 sessions, aggregate older data into statistics

---

## Recommendation Algorithm

### Scoring Formula

For each candidate skill, calculate confidence score:

```
confidence = (
  keyword_match_score * 0.40 +
  historical_success_score * 0.30 +
  priority_score * 0.20 +
  recency_score * 0.10
)
```

**Components**:

1. **Keyword Match Score** (0.0 - 1.0)
   - 1.0: All skill-specific keywords present in request
   - 0.5: Some keyword overlap
   - 0.0: No keyword overlap

2. **Historical Success Score** (0.0 - 1.0)
   - Formula: `successful_uses / total_uses` for this category + skill
   - 0.5: No historical data (neutral)
   - 1.0: 100% success rate
   - 0.0: 0% success rate (never worked)

3. **Priority Score** (0.0 - 1.0)
   - Formula: `1.0 / priority` (priority 1 = 1.0, priority 2 = 0.5, etc.)
   - Skills marked priority 1 get boost

4. **Recency Score** (0.0 - 1.0)
   - Formula: Exponential decay based on last use
   - Recently used skills get slight boost (warm cache, fresh in mind)

### Decision Thresholds

```
if confidence >= 0.85:
    → AUTO-INVOKE (high confidence, just do it)

elif confidence >= 0.60:
    → SUGGEST (medium confidence, ask user)

elif confidence >= 0.40:
    → MENTION (low-medium confidence, inform but don't push)

else:
    → SILENT (low confidence, don't recommend)
```

---

## Implementation Phases

### Phase 1: Core Recommendation Engine (2-3 hours)

**Session 5D-1: Build Classifier & Scorer**

**Tasks**:
1. Create `scripts/recommend-skill.sh` (400 lines)
   - Task classifier
   - Keyword extraction
   - Recommendation scorer
   - Output formatter

2. Create `.claude/context/task-skill-map.json`
   - Define 8 task categories
   - Map skills to categories
   - Include keyword lists

3. Create `.claude/context/skill-usage.json` (empty initially)

4. Test classification:
   ```bash
   # Test DEBUGGING
   ./scripts/recommend-skill.sh "Jellyfin won't start, seeing permission errors"
   # Expected: systematic-debugging (high confidence)

   # Test DEPLOYMENT
   ./scripts/recommend-skill.sh "I want to deploy Immich for photo management"
   # Expected: homelab-deployment (high confidence)

   # Test MONITORING
   ./scripts/recommend-skill.sh "What's the health of my system?"
   # Expected: homelab-intelligence (high confidence)
   ```

**Success Criteria**:
- ✅ All test cases classify correctly
- ✅ Confidence scores are reasonable (>0.7 for obvious cases)
- ✅ Output is clear and actionable
- ✅ Files created in `.claude/context/`

**Deliverables**:
- `scripts/recommend-skill.sh` (executable)
- `.claude/context/task-skill-map.json`
- `.claude/context/skill-usage.json`

---

### Phase 2: Usage Tracking & Learning (2-3 hours)

**Session 5D-2: Implement Learning Loop**

**Tasks**:
1. Add usage logging to `scripts/recommend-skill.sh`:
   - After skill invocation, log to skill-usage.json
   - Record: category, skill, keywords, outcome

2. Create `scripts/analyze-skill-usage.sh` (150 lines):
   - Generate usage statistics
   - Identify most/least used skills
   - Calculate success rates per skill
   - Output recommendations for improvement

3. Add historical scoring:
   - Update `calculate_historical_score()` to use skill-usage.json
   - Boost confidence for skills with proven track record

4. Test learning:
   ```bash
   # Simulate usage history
   echo '{"sessions": [...]}' > skill-usage.json

   # Verify historical score increases
   ./scripts/recommend-skill.sh "Debug jellyfin issue"
   # Should show higher confidence for systematic-debugging if history shows success
   ```

**Success Criteria**:
- ✅ Usage logging works automatically
- ✅ Historical data improves recommendations
- ✅ analyze-skill-usage.sh generates accurate statistics
- ✅ Confidence scores adjust based on history

**Deliverables**:
- Updated `scripts/recommend-skill.sh` with logging
- `scripts/analyze-skill-usage.sh`
- Populated `skill-usage.json` with test data

---

### Phase 3: Auto-Invocation Integration (1-2 hours)

**Session 5D-3: Hook into Claude Code**

**Tasks**:
1. Create wrapper script for skill invocation:
   ```bash
   # scripts/auto-recommend-skill.sh
   # Called by Claude before processing user request
   # If high confidence, auto-invoke skill
   ```

2. Update CLAUDE.md with skill recommendation guidance:
   ```markdown
   ## Skill Recommendation

   Before processing user requests, ALWAYS run:
   ./scripts/recommend-skill.sh "$USER_REQUEST"

   If output includes "AUTO_INVOKE:skill-name":
   - Invoke the skill immediately
   - Inform user: "I'm using the [skill-name] skill for this task."

   If confidence >= 60% but < 85%:
   - Ask user: "Would you like me to use the [skill-name] skill? It's designed for [purpose]."
   ```

3. Test auto-invocation:
   - Use obvious debugging request
   - Verify systematic-debugging is auto-invoked
   - Verify user is informed

**Success Criteria**:
- ✅ High-confidence tasks auto-invoke skills
- ✅ Medium-confidence tasks suggest skills
- ✅ User is always informed of skill usage
- ✅ No skill invocation for low-confidence tasks

**Deliverables**:
- Updated CLAUDE.md with recommendation logic
- `scripts/auto-recommend-skill.sh` wrapper
- Integration tests passed

---

## Integration Points

### 1. CLAUDE.md (Project Instructions)

**Enhancement**: Add skill recommendation logic to project instructions.

**Before**:
```markdown
Claude decides manually when to use skills (inconsistent)
```

**After**:
```markdown
## Skill Recommendation Engine

Before processing user requests, run: ./scripts/recommend-skill.sh "$USER_REQUEST"

Invocation Rules:
- confidence >= 85%: AUTO-INVOKE (inform user)
- confidence >= 60%: SUGGEST (ask user)
- confidence < 60%: MANUAL (use your judgment)

Example:
User: "Jellyfin won't start"
→ recommend-skill.sh returns: systematic-debugging (92%)
→ Auto-invoke: /skill systematic-debugging
```

---

### 2. Skill Usage Analytics

**Integration**: Generate monthly skill usage reports.

**Implementation**:
```bash
# scripts/generate-skill-report.sh
# Creates: docs/99-reports/YYYY-MM-skill-usage-report.md

# Contents:
# - Total invocations per skill
# - Success rate per skill
# - Most common task categories
# - Underutilized skills
# - Recommendations for improvement
```

---

### 3. Homelab-Intelligence Skill

**Enhancement**: Add skill usage insights.

**Example**:
```
User: "What skills do I use the most?"

Claude (via homelab-intelligence + skill-usage.json):
"Based on the last 100 sessions:

Top 3 Skills:
1. homelab-intelligence: 45 uses (35%)
2. homelab-deployment: 38 uses (30%)
3. systematic-debugging: 32 uses (25%)

Most Common Tasks:
1. MONITORING: 45 sessions
2. DEPLOYMENT: 38 sessions
3. DEBUGGING: 32 sessions

Recommendations:
- git-advanced-workflows is underutilized (8 uses)
  Consider using for complex git operations
"
```

---

## Testing Strategy

### Unit Tests

**Test 1: Keyword Extraction**
```bash
extract_keywords "Jellyfin won't start, seeing permission errors in logs"
# Expected: jellyfin, won't, start, seeing, permission, errors, logs
```

**Test 2: Task Classification**
```bash
classify_task "error fail broken debug"
# Expected: DEBUGGING

classify_task "deploy install setup new"
# Expected: DEPLOYMENT
```

**Test 3: Confidence Scoring**
```bash
# High confidence (obvious match)
recommend-skill.sh "Debug jellyfin error"
# Expected: systematic-debugging (>0.85)

# Low confidence (ambiguous)
recommend-skill.sh "Update something"
# Expected: <0.60 confidence
```

---

### Integration Tests

**Test 1: Full Recommendation Flow**
```bash
# Clear usage history
echo '{"sessions": []}' > skill-usage.json

# Run recommendation
result=$(./scripts/recommend-skill.sh "Jellyfin service won't start, permission denied error")

# Verify
echo "$result" | grep -q "systematic-debugging"
echo "$result" | grep -q "AUTO_INVOKE"
```

**Test 2: Historical Learning**
```bash
# Populate history (10 successful systematic-debugging uses)
# Run recommendation for similar task
# Verify confidence increased
```

---

## Success Metrics

### Quantitative Metrics

1. **Skill Utilization Rate**
   - Before: ~20% of tasks use skills (manual invocation)
   - Target: >70% of tasks use skills (auto-recommendation)

2. **Recommendation Accuracy**
   - Target: >85% of auto-invocations are appropriate (user doesn't override)
   - Measure: Track user overrides/cancellations

3. **Time to Skill Invocation**
   - Before: 30-60 seconds (Claude decides manually)
   - After: <5 seconds (instant recommendation)

### Qualitative Metrics

1. **User Experience**
   - "Claude always uses the right skill for the job"
   - "I don't have to remember which skill does what"

2. **Skill Discoverability**
   - Users learn about skills through recommendations
   - Underutilized skills get exposure via suggestions

---

## Future Enhancements

### Enhancement 1: Skill Composition

**Problem**: Some tasks require multiple skills.

**Example**: "Deploy Immich and monitor its health"
- Needs: homelab-deployment + homelab-intelligence

**Solution**: Recommend skill sequences.

---

### Enhancement 2: User Feedback Loop

**Enhancement**: Ask user after skill use: "Was this helpful?"

**Implementation**:
```bash
# After skill completes
echo "Was the systematic-debugging skill helpful? (y/n)"
# Store feedback in skill-usage.json
# Adjust future recommendations
```

---

### Enhancement 3: Skill Metadata Enrichment

**Enhancement**: Skills declare their own capabilities.

**Implementation**: Each skill includes metadata:
```yaml
# .claude/skills/systematic-debugging/metadata.yml
name: systematic-debugging
categories:
  - DEBUGGING
keywords:
  - error
  - fail
  - broken
  - troubleshoot
conditions:
  - has_error_logs
success_rate_target: 0.85
```

---

## Documentation

### Usage Guide

**File**: `docs/10-services/guides/skill-recommendation.md`

**Contents**:
- How skill recommendation works
- Task categories and mapping
- How to add new skills to recommendation engine
- How to view usage statistics
- Troubleshooting recommendations

---

## Conclusion

Session 5D delivers an **intelligent skill recommendation engine** that:

✅ Automatically detects when skills should be used
✅ Learns from usage patterns over time
✅ Increases skill utilization from 20% to 70%+
✅ Reduces cognitive load (users don't need to remember skills)
✅ Improves consistency (right tool for the job, every time)

**Timeline**: 5-7 hours across 2-3 sessions
**Prerequisites**: Session 4 (Context Framework), existing Claude skills
**Value**: Transform skills from hidden tools into intelligent assistants

Ready to make your skills work smarter! 🧠
