#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [max_iterations]

set -e

MAX_ITERATIONS=${1:-10}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
TRANSCRIPT_DIR="$SCRIPT_DIR/transcripts"
TRANSCRIPT_INDEX="$TRANSCRIPT_DIR/index.json"
METRICS_FILE="$SCRIPT_DIR/metrics.json"

# Plugins to disable during Ralph runs (interfering with autonomous execution)
RALPH_DISABLE_PLUGINS=(
  "automatic-code-review@claude-skillz"
  "explanatory-output-style@claude-plugins-official"
)

# Configure Ralph profile by disabling interfering plugins
configure_ralph_profile() {
  echo "Configuring Ralph profile (disabling interfering plugins)..."
  for plugin in "${RALPH_DISABLE_PLUGINS[@]}"; do
    if claude plugin disable "$plugin" 2>/dev/null; then
      echo "  Disabled: $plugin"
    else
      # Plugin might not be installed - that's fine
      echo "  Skipped (not installed): $plugin"
    fi
  done
}

# Restore plugins to their original state
restore_plugins() {
  echo "Restoring plugins..."
  for plugin in "${RALPH_DISABLE_PLUGINS[@]}"; do
    if claude plugin enable "$plugin" 2>/dev/null; then
      echo "  Enabled: $plugin"
    else
      # Plugin might not be installed - that's fine
      echo "  Skipped (not installed): $plugin"
    fi
  done
}

# Trap handler for cleanup on exit (normal, error, or interrupt)
cleanup_on_exit() {
  local exit_code=$?
  restore_plugins
  exit $exit_code
}

# Register cleanup traps - EXIT covers normal exit and set -e failures
# SIGINT covers Ctrl+C interrupts
trap cleanup_on_exit EXIT
trap 'trap - EXIT; cleanup_on_exit' INT

# Print metrics summary on loop completion
print_metrics_summary() {
  if [ ! -f "$METRICS_FILE" ] || [ ! -s "$METRICS_FILE" ]; then
    echo "No metrics data available."
    return
  fi

  local total_iterations successful_stories blocked_stories failed_iterations
  local total_duration avg_duration

  total_iterations=$(jq '.iterations | length' "$METRICS_FILE")
  successful_stories=$(jq '[.iterations[] | select(.status == "success")] | length' "$METRICS_FILE")
  blocked_stories=$(jq '[.iterations[] | select(.status == "blocked")] | length' "$METRICS_FILE")
  failed_iterations=$(jq '[.iterations[] | select(.status == "failed")] | length' "$METRICS_FILE")
  total_duration=$(jq '[.iterations[].duration_seconds] | add // 0' "$METRICS_FILE")

  if [ "$total_iterations" -gt 0 ]; then
    avg_duration=$((total_duration / total_iterations))
  else
    avg_duration=0
  fi

  # Format duration as human-readable
  local total_mins=$((total_duration / 60))
  local total_secs=$((total_duration % 60))
  local avg_mins=$((avg_duration / 60))
  local avg_secs=$((avg_duration % 60))

  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  RALPH METRICS SUMMARY"
  echo "═══════════════════════════════════════════════════════"
  echo "  Total iterations:     $total_iterations"
  echo "  Successful stories:   $successful_stories"
  echo "  Blocked stories:      $blocked_stories"
  echo "  Failed iterations:    $failed_iterations"
  echo "  Total duration:       ${total_mins}m ${total_secs}s"
  echo "  Average time/story:   ${avg_mins}m ${avg_secs}s"
  echo "═══════════════════════════════════════════════════════"
}

# Record metrics for an iteration
# Arguments: status story_id failure_reason
record_metrics() {
  local status="$1"
  local story_id="$2"
  local failure_reason="${3:-}"

  local iteration_end
  iteration_end=$(date +%s)
  local duration=$((iteration_end - ITERATION_START))

  # Calculate lines changed and files changed from git diff
  local lines_changed files_changed
  # Use awk instead of bc (bc may not be installed)
  lines_changed=$(git diff --stat HEAD~1 2>/dev/null | tail -1 | awk '{ins=$1; del=$4; total=(ins+0)+(del+0); print (total>0 ? total : 0)}')
  lines_changed=${lines_changed:-0}
  files_changed=$(git diff --stat HEAD~1 2>/dev/null | grep -c '|' 2>/dev/null || echo "0")

  # Estimate tokens from transcript word count (words × 1.3)
  # Use bash arithmetic instead of bc: (words * 13) / 10
  local word_count estimated_tokens
  word_count=$(wc -w < "$TRANSCRIPT_FILE" 2>/dev/null | tr -d ' ' || echo "0")
  word_count=${word_count:-0}
  estimated_tokens=$(( (word_count * 13) / 10 ))

  # Append metrics to JSON file
  jq --arg ts "$TIMESTAMP" \
     --argjson dur "$duration" \
     --arg sid "$story_id" \
     --arg st "$status" \
     --argjson lc "$lines_changed" \
     --argjson fc "$files_changed" \
     --argjson et "$estimated_tokens" \
     --arg fr "$failure_reason" \
     '.iterations += [{"timestamp": $ts, "duration_seconds": $dur, "story_id": $sid, "status": $st, "lines_changed": $lc, "files_changed": $fc, "estimated_tokens": $et, "failure_reason": $fr}]' \
     "$METRICS_FILE" > "$METRICS_FILE.tmp" && mv "$METRICS_FILE.tmp" "$METRICS_FILE"
}

# Initialize transcript directory and index
mkdir -p "$TRANSCRIPT_DIR"
if [ ! -f "$TRANSCRIPT_INDEX" ]; then
  echo '{"transcripts": []}' > "$TRANSCRIPT_INDEX"
fi

# Initialize metrics file
if [ ! -f "$METRICS_FILE" ]; then
  echo '{"iterations": []}' > "$METRICS_FILE"
fi

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")

  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    # Archive transcripts
    if [ -d "$TRANSCRIPT_DIR" ] && [ "$(ls -A "$TRANSCRIPT_DIR" 2>/dev/null)" ]; then
      cp -r "$TRANSCRIPT_DIR" "$ARCHIVE_FOLDER/"
    fi
    echo "   Archived to: $ARCHIVE_FOLDER"

    # Reset progress file for new run
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"

    # Reset transcript index for new run
    echo '{"transcripts": []}' > "$TRANSCRIPT_INDEX"
    # Remove old transcript files (keep index)
    find "$TRANSCRIPT_DIR" -name "*.txt" -delete 2>/dev/null || true
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Configure Ralph profile (disable interfering plugins) before main loop
configure_ralph_profile

echo "Starting Ralph - Max iterations: $MAX_ITERATIONS"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Ralph Iteration $i of $MAX_ITERATIONS"
  echo "═══════════════════════════════════════════════════════"

  # Capture iteration start time for metrics
  ITERATION_START=$(date +%s)

  # Generate transcript filename
  TIMESTAMP=$(date +%Y-%m-%d-%H-%M-%S)
  TRANSCRIPT_FILE="$TRANSCRIPT_DIR/$TIMESTAMP-iteration-$i.txt"

  # Run Claude with the ralph prompt, capturing to transcript
  OUTPUT=$(claude --dangerously-skip-permissions --print < "$SCRIPT_DIR/prompt.md" 2>&1 | tee /dev/stderr "$TRANSCRIPT_FILE") || true

  # Append metadata to transcript
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "unknown")
  cat >> "$TRANSCRIPT_FILE" << EOF

---
# METADATA
Iteration: $i
Timestamp: $TIMESTAMP
Branch: $CURRENT_BRANCH
EOF

  # Extract story ID from output (looks for "feat: US-001" or similar patterns)
  STORY_ID=$(echo "$OUTPUT" | grep -oP 'feat: \K[A-Za-z]+-\d+' | head -1 || echo "")
  if [ -z "$STORY_ID" ]; then
    STORY_ID=$(echo "$OUTPUT" | grep -oP '\b[A-Z]+-\d+\b' | head -1 || echo "unknown")
  fi

  # Update transcript index
  TRANSCRIPT_BASENAME=$(basename "$TRANSCRIPT_FILE")
  jq --arg file "$TRANSCRIPT_BASENAME" \
     --arg ts "$TIMESTAMP" \
     --arg iter "$i" \
     --arg branch "$CURRENT_BRANCH" \
     --arg story "$STORY_ID" \
     '.transcripts += [{"file": $file, "timestamp": $ts, "iteration": ($iter|tonumber), "branch": $branch, "storyId": $story}]' \
     "$TRANSCRIPT_INDEX" > "$TRANSCRIPT_INDEX.tmp" && mv "$TRANSCRIPT_INDEX.tmp" "$TRANSCRIPT_INDEX"

  # Verify that verification was provided (enforcement of US-003 requirement)
  # Accept either <verification> XML blocks OR ✅ checkmarks as valid verification
  VERIFICATION_FAILED=false
  FAILURE_REASON=""

  # Check if any verification exists (XML format or checkmark format)
  HAS_XML_VERIFICATION=$(echo "$OUTPUT" | grep -c "<verification>" || echo "0")
  HAS_CHECKMARK_VERIFICATION=$(echo "$OUTPUT" | grep -c "✅" || echo "0")

  if [ "$HAS_XML_VERIFICATION" -eq 0 ] && [ "$HAS_CHECKMARK_VERIFICATION" -eq 0 ]; then
    VERIFICATION_FAILED=true
    FAILURE_REASON="Missing verification - story completion requires either <verification> blocks or ✅ checkmarks"
  else
    # Check for NOT_SATISFIED conclusions (XML format) or ❌ (checkmark format)
    if echo "$OUTPUT" | grep -q "Conclusion: NOT_SATISFIED"; then
      VERIFICATION_FAILED=true
      FAILURE_REASON="Verification failed - one or more criteria marked NOT_SATISFIED"
    fi
    if echo "$OUTPUT" | grep -q "❌"; then
      VERIFICATION_FAILED=true
      FAILURE_REASON="Verification failed - one or more criteria marked with ❌"
    fi
  fi

  # If verification failed, log to transcript and skip counting this as success
  if [ "$VERIFICATION_FAILED" = true ]; then
    echo ""
    echo "⚠ VERIFICATION ENFORCEMENT FAILED"
    echo "  Reason: $FAILURE_REASON"
    echo "  This iteration does not count toward story completion."

    # Append failure reason to transcript
    cat >> "$TRANSCRIPT_FILE" << EOF
# VERIFICATION ENFORCEMENT
Status: FAILED
Reason: $FAILURE_REASON
EOF

    # Record failed iteration metrics
    record_metrics "failed" "$STORY_ID" "$FAILURE_REASON"

    echo "Iteration $i failed verification. Continuing..."
    sleep 2
    continue
  fi

  # Record successful iteration metrics
  record_metrics "success" "$STORY_ID" ""

  # Check for completion signal
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Ralph completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    print_metrics_summary
    exit 0
  fi

  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
print_metrics_summary
exit 1
