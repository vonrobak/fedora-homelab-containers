# Skill Recommendation Engine

**Status:** ✅ Production-Ready (Implemented 2025-11-30)
**Location:** `~/containers/scripts/recommend-skill.sh`

## Overview

The skill recommendation engine analyzes user requests and system state to recommend the most appropriate Claude skill(s). It implements task classification, confidence scoring, and usage tracking to improve recommendations over time.

## Quick Start

```bash
# Get skill recommendation for a request
./scripts/recommend-skill.sh "Jellyfin won't start, seeing permission errors"

# JSON output (for scripting)
./scripts/recommend-skill.sh --json "Deploy a new wiki service"

# View usage statistics
./scripts/recommend-skill.sh --stats

# Log skill usage (after using a skill)
./scripts/recommend-skill.sh --log systematic-debugging success DEBUGGING "jellyfin error"
```

## Available Skills

The engine maps requests to 6 available Claude skills:

| Skill | Category | Use For |
|-------|----------|---------|
| `systematic-debugging` | DEBUGGING | Errors, failures, troubleshooting |
| `homelab-deployment` | DEPLOYMENT | New services, configuration |
| `homelab-intelligence` | MONITORING | Health checks, diagnostics |
| `git-advanced-workflows` | GIT_OPERATIONS | Rebasing, conflicts, recovery |
| `claude-code-analyzer` | OPTIMIZATION | Claude Code workflow improvement |
| `autonomous-operations` | AUTONOMOUS | Automated system operations |

## Task Categories

The engine classifies requests into 8 categories:

1. **DEBUGGING** - Service failures, errors, troubleshooting
2. **DEPLOYMENT** - New service installation, configuration
3. **MONITORING** - Health checks, system analysis, diagnostics
4. **GIT_OPERATIONS** - Complex git workflows, conflict resolution
5. **OPTIMIZATION** - Performance tuning, workflow improvement
6. **CONFIGURATION** - Service configuration changes
7. **AUTONOMOUS** - System operations, maintenance
8. **QUESTION** - Information requests, how-to questions

## Confidence Scoring

The engine calculates confidence using four factors:

```
confidence = (
  category_match_score * 0.40 +    # How well keywords match category
  skill_keyword_bonus * 0.25 +      # Skill-specific keyword matches
  historical_success_rate * 0.25 + # Past success with this skill
  priority_score * 0.10             # Skill priority for category
)
```

### Invocation Strategies

| Confidence | Strategy | Behavior |
|------------|----------|----------|
| ≥ 85% | AUTO | Skill should be invoked automatically |
| ≥ 60% | SUGGEST | Recommend the skill to user |
| ≥ 40% | MENTION | Consider using this skill |
| < 40% | NONE | No strong recommendation |

## Usage Tracking

Every skill invocation can be logged to improve future recommendations:

```bash
# After successful debugging session
./scripts/recommend-skill.sh --log systematic-debugging success DEBUGGING "container restart issue"

# After failed deployment attempt
./scripts/recommend-skill.sh --log homelab-deployment failure DEPLOYMENT "immich deploy"

# View statistics
./scripts/recommend-skill.sh --stats
```

### Statistics Output

```
=== Skill Usage Statistics ===

Total invocations: 15

By Skill:
  systematic-debugging: 6
  homelab-deployment: 5
  homelab-intelligence: 4

By Category:
  DEBUGGING: 6
  DEPLOYMENT: 5
  MONITORING: 4

Success rate: 87.0%
```

## Integration with Autonomous Operations

The skill recommendation engine is integrated with `autonomous-check.sh`. During the DECIDE phase, it recommends skills based on observed system state:

```bash
# Run autonomous check
./scripts/autonomous-check.sh --json

# Output includes skill recommendations:
{
  "skill_recommendations": {
    "category": "MONITORING",
    "top_recommendation": {
      "skill": "homelab-intelligence",
      "confidence": 0.52,
      "invocation": "mention"
    }
  }
}
```

### Automatic Skill Mapping

| System State | Recommended Skill |
|--------------|-------------------|
| Unhealthy services | systematic-debugging |
| Configuration drift | homelab-deployment |
| High disk usage | homelab-intelligence |
| Service errors | systematic-debugging |

## Configuration Files

### Task-Skill Map

**Location:** `~/.claude/context/task-skill-map.json`

Defines:
- Task categories and their keywords
- Skill mappings with priorities
- Skill metadata and conditions

### Skill Usage Log

**Location:** `~/.claude/context/skill-usage.json`

Tracks:
- Session history with timestamps
- Skill invocations by category
- Success/failure outcomes
- Aggregate statistics

## Examples

### Debugging Scenario

```bash
$ ./scripts/recommend-skill.sh "Container keeps crashing with OOM errors"

=== Skill Recommendation ===

Task Category: DEBUGGING (22% match)

Recommended Skill: systematic-debugging (63% confidence)
Invocation: SUGGEST - Recommend using this skill
Description: Four-phase debugging framework

All Recommendations:
  systematic-debugging: 63% - Four-phase debugging framework
  homelab-intelligence: 45% - System health analysis
```

### Deployment Scenario

```bash
$ ./scripts/recommend-skill.sh "Deploy a new Paperless-ngx document management system"

=== Skill Recommendation ===

Task Category: DEPLOYMENT (19% match)

Recommended Skill: homelab-deployment (58% confidence)
Invocation: MENTION - Consider using this skill
Description: Pattern-based service deployment
```

### JSON for Scripting

```bash
$ ./scripts/recommend-skill.sh --json "Check system health" | jq '.top_recommendation'

{
  "skill": "homelab-intelligence",
  "confidence": 0.56,
  "invocation": "mention"
}
```

## Architecture

```
User Request
     │
     ▼
┌─────────────────────────────────┐
│   Keyword Extraction            │
│   (remove stopwords, normalize) │
└─────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────┐
│   Task Classification           │
│   (match keywords to category)  │
└─────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────┐
│   Skill Scoring                 │
│   (confidence calculation)      │
└─────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────┐
│   Invocation Decision           │
│   (auto/suggest/mention/none)   │
└─────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────┐
│   Usage Logging                 │
│   (improve future recs)         │
└─────────────────────────────────┘
```

## Extending the System

### Adding New Skills

1. Add skill entry to `task-skill-map.json`:
```json
{
  "name": "new-skill",
  "priority": 1,
  "conditions": [],
  "description": "What this skill does"
}
```

2. Add skill metadata:
```json
"skill_metadata": {
  "new-skill": {
    "full_name": "New Skill Name",
    "features": ["feature1", "feature2"],
    "ideal_for": "Use case description"
  }
}
```

3. Add keyword bonus in `recommend-skill.sh`:
```bash
new-skill)
    if echo "$keywords" | grep -qE '(relevant|keywords)' 2>/dev/null; then
        echo "1.0"
    else
        echo "0.4"
    fi
    ;;
```

### Adding New Categories

1. Add category to `task-skill-map.json`:
```json
{
  "category": "NEW_CATEGORY",
  "description": "What this category covers",
  "keywords": ["keyword1", "keyword2", ...],
  "skills": [...]
}
```

## References

- Session 5D Plan: `docs/99-reports/SESSION-5D-SKILL-RECOMMENDATION-ENGINE-PLAN.md`
- Autonomous Operations: `docs/20-operations/guides/autonomous-operations.md`
- Available Skills: `.claude/skills/*/SKILL.md`
