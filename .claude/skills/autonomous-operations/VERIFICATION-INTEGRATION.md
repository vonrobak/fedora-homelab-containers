# Verification Integration Guide

**Purpose:** Document how to integrate verification feedback loops into autonomous-execute.sh

**Status:** Design documentation - ready for implementation

**Safety:** These changes should be implemented incrementally with testing between each phase.

---

## Overview

This guide shows how to add verification and confidence learning to autonomous-execute.sh, creating a feedback loop where the system learns from action outcomes.

**Key changes:**
1. Capture before-state before action execution
2. Run verification after action completes
3. Update confidence scores based on verification results
4. Log verification details in decision log
5. Auto-rollback if verification fails

---

## Phase 1: Capture Before-State

**Location:** After snapshot creation, before action execution

**Add after line where BTRFS snapshot is created:**

```bash
# Existing: Create BTRFS snapshot
SNAPSHOT_NAME="autonomous-${ACTION_TYPE}-${SERVICE}-$(date +%s)"
sudo btrfs subvolume snapshot \
  /mnt/btrfs-pool/subvol7-containers \
  /mnt/btrfs-pool/.snapshots/${SNAPSHOT_NAME}

# NEW: Capture before-state for verification
BEFORE_STATE="/tmp/before-state-${ACTION_ID}.json"
~/containers/scripts/homelab-intel.sh --quiet --json > "$BEFORE_STATE" 2>/dev/null || {
  echo "Warning: Could not capture before-state, verification may be limited"
  echo '{}' > "$BEFORE_STATE"
}

# For service-specific actions, also capture service name
if [[ "$ACTION_TYPE" == "service-restart" ]] || [[ "$ACTION_TYPE" == "drift-reconciliation" ]]; then
  # Add service name to before-state for verification
  jq --arg service "$SERVICE" '. + {service: $service}' "$BEFORE_STATE" > "${BEFORE_STATE}.tmp"
  mv "${BEFORE_STATE}.tmp" "$BEFORE_STATE"
fi
```

---

## Phase 2: Execute Action (Unchanged)

**No changes to existing action execution code.**

The action executes normally via playbooks or skills. Existing error handling remains.

---

## Phase 3: Wait for Stabilization

**Location:** After action execution, before verification

**Add after action execution completes:**

```bash
# Existing: Check action exit code
if [[ $ACTION_EXIT_CODE -eq 0 ]]; then
  # NEW: Wait for system to stabilize before verification
  case "$ACTION_TYPE" in
    disk-cleanup|predictive-maintenance)
      STABILIZATION_DELAY=10  # Filesystem operations are fast
      ;;
    service-restart)
      STABILIZATION_DELAY=30  # Services need time to fully start
      ;;
    drift-reconciliation)
      STABILIZATION_DELAY=20  # Config changes need reload time
      ;;
    resource-pressure)
      STABILIZATION_DELAY=30  # Memory release takes time
      ;;
    *)
      STABILIZATION_DELAY=15  # Default
      ;;
  esac

  echo "Waiting ${STABILIZATION_DELAY}s for system stabilization..."
  sleep "$STABILIZATION_DELAY"

  # Continue to verification...
fi
```

---

## Phase 4: Run Verification

**Location:** After stabilization, before logging

**Add verification based on action type:**

```bash
# NEW: Verify action outcome
echo "Verifying action outcome..."

VERIFICATION_PASSED=false
VERIFICATION_STATUS="unknown"
VERIFICATION_CONFIDENCE=0
VERIFICATION_DETAILS=""

case "$ACTION_TYPE" in
  disk-cleanup|predictive-maintenance|resource-pressure)
    # Use verify-autonomous-outcome.sh for resource-based actions
    if ~/containers/scripts/verify-autonomous-outcome.sh \
         "$ACTION_TYPE" \
         "$BEFORE_STATE" \
         0; then  # Already waited during stabilization
      VERIFICATION_PASSED=true
      VERIFICATION_STATUS="VERIFIED"
      VERIFICATION_CONFIDENCE=95
      VERIFICATION_DETAILS="Outcome verified: improvement detected"
    else
      VERIFICATION_EXIT_CODE=$?
      if [[ $VERIFICATION_EXIT_CODE -eq 2 ]]; then
        # Unknown action type - skip verification
        VERIFICATION_PASSED=true
        VERIFICATION_STATUS="SKIPPED"
        VERIFICATION_CONFIDENCE=50
        VERIFICATION_DETAILS="Verification not available for this action type"
      else
        # Verification failed
        VERIFICATION_PASSED=false
        VERIFICATION_STATUS="FAILED"
        VERIFICATION_CONFIDENCE=30
        VERIFICATION_DETAILS="Outcome verification failed: no improvement detected"
      fi
    fi
    ;;

  service-restart|drift-reconciliation)
    # Use verify-autonomous-outcome.sh first
    if ~/containers/scripts/verify-autonomous-outcome.sh \
         "$ACTION_TYPE" \
         "$BEFORE_STATE" \
         0; then
      # Basic verification passed, run comprehensive service verification
      if [[ -f ~/.claude/skills/homelab-deployment/scripts/verify-deployment.sh ]]; then
        # Extract external URL if service is public
        EXTERNAL_URL=""
        if [[ -f ~/containers/config/traefik/dynamic/routers.yml ]]; then
          EXTERNAL_URL=$(grep -A 5 "${SERVICE}-secure:" ~/containers/config/traefik/dynamic/routers.yml | grep "Host(" | sed 's/.*Host(`\([^`]*\)`.*/https:\/\/\1/' || echo "")
        fi

        # Run comprehensive verification
        VERIFICATION_REPORT="/tmp/verification-${SERVICE}-$(date +%s).txt"
        if ~/.claude/skills/homelab-deployment/scripts/verify-deployment.sh \
             "$SERVICE" \
             "$EXTERNAL_URL" \
             true > "$VERIFICATION_REPORT" 2>&1; then
          VERIFICATION_PASSED=true
          VERIFICATION_STATUS="VERIFIED"
          VERIFICATION_CONFIDENCE=95
          VERIFICATION_DETAILS="Service verification passed (7-level framework)"
        else
          VERIFICATION_PASSED=false
          VERIFICATION_STATUS="FAILED"
          VERIFICATION_CONFIDENCE=40
          VERIFICATION_DETAILS="Service verification failed. See: $VERIFICATION_REPORT"
        fi
      else
        # Fallback if verify-deployment.sh not found
        VERIFICATION_PASSED=true
        VERIFICATION_STATUS="VERIFIED"
        VERIFICATION_CONFIDENCE=70
        VERIFICATION_DETAILS="Basic outcome verified (comprehensive check unavailable)"
      fi
    else
      VERIFICATION_PASSED=false
      VERIFICATION_STATUS="FAILED"
      VERIFICATION_CONFIDENCE=30
      VERIFICATION_DETAILS="Outcome verification failed"
    fi
    ;;

  *)
    # Unknown action type - skip verification but don't fail
    VERIFICATION_PASSED=true
    VERIFICATION_STATUS="SKIPPED"
    VERIFICATION_CONFIDENCE=50
    VERIFICATION_DETAILS="No verification available for action type: $ACTION_TYPE"
    ;;
esac

echo "Verification status: $VERIFICATION_STATUS (confidence: $VERIFICATION_CONFIDENCE%)"
```

---

## Phase 5: Update Confidence Scores

**Location:** After verification, before decision logging

**Calculate confidence delta and update scores:**

```bash
# NEW: Calculate confidence delta based on verification result
CONFIDENCE_DELTA=0

if [[ "$VERIFICATION_PASSED" == "true" ]]; then
  if [[ "$VERIFICATION_STATUS" == "VERIFIED" ]] && [[ $VERIFICATION_CONFIDENCE -ge 90 ]]; then
    # Full verification success
    CONFIDENCE_DELTA=5
    echo "Verification passed: confidence +5%"
  elif [[ "$VERIFICATION_STATUS" == "VERIFIED" ]] && [[ $VERIFICATION_CONFIDENCE -ge 70 ]]; then
    # Partial success (warnings)
    CONFIDENCE_DELTA=2
    echo "Verification passed with warnings: confidence +2%"
  elif [[ "$VERIFICATION_STATUS" == "SKIPPED" ]]; then
    # No change for skipped verification
    CONFIDENCE_DELTA=0
    echo "Verification skipped: confidence unchanged"
  fi
else
  # Verification failed
  CONFIDENCE_DELTA=-10
  echo "Verification FAILED: confidence -10%"
fi

# Update confidence for this action type
if [[ -f ~/.claude/context/confidence-scores.json ]]; then
  # Load current confidence
  CURRENT_CONFIDENCE=$(jq -r ".\"${ACTION_TYPE}\".current // 0.85" ~/.claude/context/confidence-scores.json)

  # Calculate new confidence (as decimal)
  NEW_CONFIDENCE=$(echo "$CURRENT_CONFIDENCE + ($CONFIDENCE_DELTA / 100)" | bc -l)

  # Clamp between 0.50 and 1.00
  if (( $(echo "$NEW_CONFIDENCE > 1.00" | bc -l) )); then
    NEW_CONFIDENCE=1.00
  elif (( $(echo "$NEW_CONFIDENCE < 0.50" | bc -l) )); then
    NEW_CONFIDENCE=0.50
  fi

  # Update confidence scores file
  jq --arg action "$ACTION_TYPE" \
     --arg conf "$NEW_CONFIDENCE" \
     --arg delta "$CONFIDENCE_DELTA" \
     --arg verified "$VERIFICATION_PASSED" \
     '.[$action] += {
       current: ($conf | tonumber),
       last_updated: (now | todateiso8601),
       last_delta: ($delta | tonumber),
       last_verified: ($verified == "true")
     }' ~/.claude/context/confidence-scores.json > ~/.claude/context/confidence-scores.json.tmp

  mv ~/.claude/context/confidence-scores.json.tmp ~/.claude/context/confidence-scores.json

  echo "Updated confidence: ${ACTION_TYPE} = ${NEW_CONFIDENCE} (delta: ${CONFIDENCE_DELTA}%)"
else
  echo "Warning: confidence-scores.json not found, cannot update confidence"
fi
```

---

## Phase 6: Auto-Rollback on Verification Failure

**Location:** After confidence update, before final logging

**Rollback if verification failed:**

```bash
# NEW: Auto-rollback if verification failed
if [[ "$VERIFICATION_PASSED" == "false" ]]; then
  echo "========================================="
  echo "VERIFICATION FAILED - INITIATING ROLLBACK"
  echo "========================================="
  echo "Reason: $VERIFICATION_DETAILS"
  echo ""

  # Rollback to snapshot
  echo "Rolling back to snapshot: $SNAPSHOT_NAME"

  # Stop affected service if applicable
  if [[ -n "$SERVICE" ]]; then
    systemctl --user stop "${SERVICE}.service" || true
  fi

  # Restore snapshot (this is a placeholder - actual command depends on setup)
  # In practice, you might restore specific directories or trigger a restoration process
  echo "Restoring from BTRFS snapshot..."
  # sudo btrfs subvolume delete /path/to/current || true
  # sudo btrfs subvolume snapshot /mnt/btrfs-pool/.snapshots/${SNAPSHOT_NAME} /path/to/current

  # Restart service if applicable
  if [[ -n "$SERVICE" ]]; then
    systemctl --user daemon-reload
    systemctl --user start "${SERVICE}.service" || true
  fi

  # Update outcome
  OUTCOME="failure"
  OUTCOME_DETAILS="Verification failed: $VERIFICATION_DETAILS. Rolled back to snapshot: $SNAPSHOT_NAME"

  # Increment circuit breaker
  update_circuit_breaker

  echo "Rollback complete. Service restored to pre-action state."
else
  OUTCOME="success"
  OUTCOME_DETAILS="Action executed and verified successfully: $VERIFICATION_DETAILS"
fi
```

---

## Phase 7: Enhanced Decision Logging

**Location:** Existing decision log write, enhance with verification data

**Update decision log entry:**

```bash
# Existing decision log write, enhanced with verification data
log_decision() {
  local decision_id="$1"
  local outcome="$2"
  local details="$3"

  # Build decision log entry with verification data
  DECISION_ENTRY=$(jq -n \
    --arg id "$decision_id" \
    --arg timestamp "$(date -Iseconds)" \
    --arg action_type "$ACTION_TYPE" \
    --arg service "$SERVICE" \
    --arg trigger "$TRIGGER" \
    --arg confidence "$CONFIDENCE" \
    --arg risk "$RISK" \
    --arg decision "$DECISION" \
    --arg outcome "$outcome" \
    --arg details "$details" \
    --arg verification_status "$VERIFICATION_STATUS" \
    --arg verification_confidence "$VERIFICATION_CONFIDENCE" \
    --arg verification_details "$VERIFICATION_DETAILS" \
    --arg confidence_delta "$CONFIDENCE_DELTA" \
    --arg new_confidence "$NEW_CONFIDENCE" \
    --arg duration "$DURATION" \
    '{
      id: $id,
      timestamp: $timestamp,
      action_type: $action_type,
      service: $service,
      trigger: $trigger,
      confidence: ($confidence | tonumber),
      risk: $risk,
      decision: $decision,
      outcome: $outcome,
      details: $details,
      verification: {
        status: $verification_status,
        confidence: ($verification_confidence | tonumber),
        details: $verification_details
      },
      confidence_delta: ($confidence_delta | tonumber),
      new_confidence: ($new_confidence | tonumber),
      duration_seconds: ($duration | tonumber)
    }')

  # Append to decision log
  if [[ -f ~/.claude/context/decision-log.json ]]; then
    jq ".decisions += [$DECISION_ENTRY]" ~/.claude/context/decision-log.json > ~/.claude/context/decision-log.json.tmp
    mv ~/.claude/context/decision-log.json.tmp ~/.claude/context/decision-log.json
  else
    echo "{\"decisions\": [$DECISION_ENTRY]}" > ~/.claude/context/decision-log.json
  fi
}
```

---

## Phase 8: Update Autonomous State File

**Location:** End of script, update state file with verification metrics

**Add verification tracking to state:**

```bash
# NEW: Update autonomous state with verification metrics
update_autonomous_state_with_verification() {
  if [[ -f ~/.claude/context/autonomous-state.json ]]; then
    # Calculate 7-day verification pass rate
    SEVEN_DAYS_AGO=$(date -d '7 days ago' -Iseconds)
    PASS_RATE=$(jq -r "
      [.decisions[] |
       select(.timestamp > \"$SEVEN_DAYS_AGO\") |
       select(.verification.status == \"VERIFIED\")] | length /
      ([.decisions[] |
        select(.timestamp > \"$SEVEN_DAYS_AGO\")] | length)
    " ~/.claude/context/decision-log.json 2>/dev/null || echo "0")

    # Count failures requiring rollback
    ROLLBACK_COUNT=$(jq -r "
      [.decisions[] |
       select(.timestamp > \"$SEVEN_DAYS_AGO\") |
       select(.verification.status == \"FAILED\")] | length
    " ~/.claude/context/decision-log.json 2>/dev/null || echo "0")

    # Update state file
    jq --arg pass_rate "$PASS_RATE" \
       --arg rollback_count "$ROLLBACK_COUNT" \
       --arg last_verification "$(date -Iseconds)" \
       '.verification = {
         enabled: true,
         last_verification: $last_verification,
         verification_pass_rate_7d: ($pass_rate | tonumber),
         failures_requiring_rollback: ($rollback_count | tonumber)
       }' ~/.claude/context/autonomous-state.json > ~/.claude/context/autonomous-state.json.tmp

    mv ~/.claude/context/autonomous-state.json.tmp ~/.claude/context/autonomous-state.json
  fi
}

# Call at end of script
update_autonomous_state_with_verification
```

---

## Implementation Checklist

### Prerequisites
- [ ] Verification scripts tested (verify-security-posture.sh, verify-monitoring.sh, verify-autonomous-outcome.sh)
- [ ] Service-validator subagent working
- [ ] Backup/snapshot system tested
- [ ] Decision log format finalized

### Phase 1: Testing Setup
- [ ] Create test confidence-scores.json file
- [ ] Create test autonomous-state.json with verification fields
- [ ] Test verify-autonomous-outcome.sh with sample before-states

### Phase 2: Implement in Stages
- [ ] Stage 1: Add before-state capture only (no verification yet)
- [ ] Stage 2: Add verification (but don't act on results)
- [ ] Stage 3: Add confidence updates (but don't rollback)
- [ ] Stage 4: Add auto-rollback for failed verifications
- [ ] Stage 5: Full integration with decision logging

### Phase 3: Validation
- [ ] Test with disk-cleanup action (low risk)
- [ ] Test with service-restart action (medium risk)
- [ ] Test with intentional verification failure (ensure rollback works)
- [ ] Review decision logs for verification data accuracy
- [ ] Check confidence scores update correctly

### Phase 4: Monitoring
- [ ] Monitor verification pass rates for first week
- [ ] Review any rollbacks that occurred
- [ ] Tune confidence delta values if needed (+5/-10 may need adjustment)
- [ ] Document any issues or edge cases found

---

## Safety Considerations

**1. Rollback Safety**
- Always test rollback procedure before relying on it in production
- Ensure BTRFS snapshots are working correctly
- Have manual recovery procedure documented

**2. Confidence Bounds**
- Minimum confidence: 0.50 (never drop below 50%)
- Maximum confidence: 1.00 (never exceed 100%)
- Prevents extreme confidence scores

**3. Circuit Breaker Integration**
- Failed verifications should count toward circuit breaker threshold
- 3 consecutive verification failures → pause autonomy
- Manual review required after circuit breaker trips

**4. Service-Specific Handling**
- Traefik/Authelia: Never auto-rollback (service_overrides)
- Other critical services: Require manual intervention
- Non-critical services: Auto-rollback is safe

---

## Monitoring & Debugging

**Check verification status:**
```bash
# View recent verifications
jq '.decisions[] | select(.timestamp > "'$(date -d '24 hours ago' -Iseconds)'") | {action: .action_type, verification: .verification.status, confidence_delta: .confidence_delta}' ~/.claude/context/decision-log.json

# Check verification pass rate
jq '.verification.verification_pass_rate_7d' ~/.claude/context/autonomous-state.json

# View confidence trends
jq '.confidence_trends' ~/.claude/context/autonomous-state.json

# Check for rollbacks
jq '.decisions[] | select(.verification.status == "FAILED") | {timestamp, action_type, service, details}' ~/.claude/context/decision-log.json
```

**Troubleshooting verification failures:**
```bash
# Check verification scripts work
~/containers/scripts/verify-autonomous-outcome.sh disk-cleanup /tmp/test-before.json 0

# Check service-validator
~/.claude/skills/homelab-deployment/scripts/verify-deployment.sh jellyfin https://jellyfin.patriark.org true

# Review verification report
cat /tmp/verification-jellyfin-*.txt | tail -100
```

---

## Future Enhancements

**1. Machine Learning Integration**
- Track verification outcomes over time
- Use ML to predict verification success probability
- Adjust confidence thresholds based on patterns

**2. Verification Weights**
- Different action types may need different confidence deltas
- disk-cleanup: +5/-10 (current)
- service-restart: +3/-15 (more conservative)
- drift-reconciliation: +5/-8 (less penalty)

**3. Verification Timeout**
- Add timeouts to verification (currently 30s max)
- Timeout = warning, not failure
- Prevents hangs in verification

**4. Parallel Verification**
- Run multiple verification levels in parallel
- Faster total verification time
- Aggregate results

---

This integration creates a self-improving autonomous system that learns from experience, automatically corrects failures, and provides comprehensive audit trails of all actions and their outcomes.
