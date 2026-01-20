#!/bin/bash
# Angainor Wiggum - Long-running AI agent loop
# Usage: ./angainor.sh [max_iterations]

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
SCREENSHOT_DIR="$SCRIPT_DIR/screenshots"
SKILL_DIR="$HOME/.claude/skills/angainor-learnings"

# Plugins to disable during Angainor runs (interfering with autonomous execution)
ANGAINOR_DISABLE_PLUGINS=(
  "automatic-code-review@claude-skillz"
  "explanatory-output-style@claude-plugins-official"
)

# Configure Angainor profile by disabling interfering plugins
configure_angainor_profile() {
  echo "Configuring Angainor profile (disabling interfering plugins)..."
  for plugin in "${ANGAINOR_DISABLE_PLUGINS[@]}"; do
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
  for plugin in "${ANGAINOR_DISABLE_PLUGINS[@]}"; do
    if claude plugin enable "$plugin" 2>/dev/null; then
      echo "  Enabled: $plugin"
    else
      # Plugin might not be installed - that's fine
      echo "  Skipped (not installed): $plugin"
    fi
  done
}

# Track last response for error reporting
LAST_CLAUDE_OUTPUT=""
LAST_ITERATION=0

# Trap handler for cleanup on exit (normal, error, or interrupt)
cleanup_on_exit() {
  local exit_code=$?

  # If exiting with error and we have a last response, print it
  if [ "$exit_code" -ne 0 ] && [ -n "$LAST_CLAUDE_OUTPUT" ]; then
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  UNEXPECTED EXIT (code $exit_code) at iteration $LAST_ITERATION"
    echo "═══════════════════════════════════════════════════════"
    echo "Last Claude response (last 100 lines):"
    echo "───────────────────────────────────────────────────────"
    echo "$LAST_CLAUDE_OUTPUT" | tail -100
    echo "───────────────────────────────────────────────────────"
  fi

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
  echo "  ANGAINOR METRICS SUMMARY"
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
  files_changed=$(git diff --stat HEAD~1 2>/dev/null | grep -c '|' 2>/dev/null) || files_changed=0

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

# Extract and write skill candidate from iteration output
# Arguments: output_text story_id
# Returns: 0 if skill extracted, 1 if no skill or skipped
write_skill_candidate() {
  local output="$1"
  local story_id="$2"

  # Check if skill candidate block exists
  if ! echo "$output" | grep -q "<<<SKILL_CANDIDATE>>>"; then
    return 0  # No skill candidate, not an error
  fi

  # Extract the skill candidate block
  local skill_block
  skill_block=$(echo "$output" | sed -n '/<<<SKILL_CANDIDATE>>>/,/<<<END_SKILL_CANDIDATE>>>/p')

  if [ -z "$skill_block" ]; then
    echo "  ⚠ Skill candidate block found but malformed (missing end delimiter)"
    return 1
  fi

  # Extract fields using sed
  local category name description content

  category=$(echo "$skill_block" | grep "^category:" | sed 's/^category:[[:space:]]*//' | head -1)
  name=$(echo "$skill_block" | grep "^name:" | sed 's/^name:[[:space:]]*//' | head -1)
  description=$(echo "$skill_block" | grep "^description:" | sed 's/^description:[[:space:]]*//' | head -1)

  # Extract content (everything after "content:" line until end delimiter)
  content=$(echo "$skill_block" | sed -n '/^content:/,/<<<END_SKILL_CANDIDATE>>>/p' | sed '1d;$d')

  # Validate required fields
  if [ -z "$category" ]; then
    echo "  ⚠ Skill candidate missing required field: category"
    return 1
  fi
  if [ -z "$name" ]; then
    echo "  ⚠ Skill candidate missing required field: name"
    return 1
  fi
  if [ -z "$description" ]; then
    echo "  ⚠ Skill candidate missing required field: description"
    return 1
  fi
  if [ -z "$content" ]; then
    echo "  ⚠ Skill candidate missing required field: content"
    return 1
  fi

  # Validate category is in allowed list
  case "$category" in
    error-resolutions|patterns|workflows)
      ;;  # Valid category
    *)
      echo "  ⚠ Skill candidate has invalid category: $category (must be: error-resolutions, patterns, workflows)"
      return 1
      ;;
  esac

  # Check if skill already exists (no overwrites)
  local skill_file="$SKILL_DIR/$category/$name.md"
  if [ -f "$skill_file" ]; then
    echo "  ⚠ Skill already exists, skipping: $skill_file"
    return 1
  fi

  # Create category directory if needed
  mkdir -p "$SKILL_DIR/$category"

  # Get project name from prd.json
  local project_name
  project_name=$(jq -r '.project // "Unknown"' "$PRD_FILE" 2>/dev/null || echo "Unknown")

  # Write skill file with YAML frontmatter
  cat > "$skill_file" << EOF
---
name: $name
description: $description
---

$content

## Origin

- Extracted: $(date -Iseconds)
- Project: $project_name
- Story: $story_id
EOF

  echo "✓ Extracted skill: $category/$name.md"
  return 0
}

# Initialize transcript directory and index
mkdir -p "$TRANSCRIPT_DIR"
# Initialize screenshot directory for browser verification evidence
mkdir -p "$SCREENSHOT_DIR"
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
    # Strip "angainor/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^angainor/||')
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
    echo "# Angainor Progress Log" > "$PROGRESS_FILE"
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
  echo "# Angainor Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Configure Angainor profile (disable interfering plugins) before main loop
configure_angainor_profile

echo "Starting Angainor - Max iterations: $MAX_ITERATIONS"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Angainor Iteration $i of $MAX_ITERATIONS"
  echo "═══════════════════════════════════════════════════════"

  # Capture iteration start time for metrics
  ITERATION_START=$(date +%s)

  # Generate transcript filename
  TIMESTAMP=$(date +%Y-%m-%d-%H-%M-%S)
  TRANSCRIPT_FILE="$TRANSCRIPT_DIR/$TIMESTAMP-iteration-$i.txt"

  # Run Claude with retry logic for transient API errors
  MAX_RETRIES=3
  RETRY_DELAY=5
  CLAUDE_TIMEOUT=600  # 10 minutes per iteration
  CLAUDE_SUCCESS=false

  for retry in $(seq 1 $MAX_RETRIES); do
    echo "  Calling Claude API (attempt $retry/$MAX_RETRIES)..."

    # Run Claude with timeout protection to prevent hangs on crashed processes
    OUTPUT=$(timeout --signal=KILL $CLAUDE_TIMEOUT claude --dangerously-skip-permissions --print < "$SCRIPT_DIR/prompt.md" 2>&1 | tee /dev/stderr "$TRANSCRIPT_FILE") || true
    CLAUDE_EXIT_CODE=$?

    # Check for timeout (exit code 137 = killed by SIGKILL after timeout)
    if [ "$CLAUDE_EXIT_CODE" -eq 137 ] || [ "$CLAUDE_EXIT_CODE" -eq 124 ]; then
      echo ""
      echo "  ⚠ Claude process timed out after ${CLAUDE_TIMEOUT}s (attempt $retry/$MAX_RETRIES)"
      if [ "$retry" -lt "$MAX_RETRIES" ]; then
        echo "  Retrying in ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
        RETRY_DELAY=$((RETRY_DELAY * 2))
        continue
      else
        echo "  ✗ Max retries exceeded due to timeouts."
        record_metrics "failed" "TIMEOUT" "Process timed out after $MAX_RETRIES retries"
        continue 2
      fi
    fi

    # Check for transient API errors
    if echo "$OUTPUT" | grep -qE "No messages returned|ECONNRESET|ETIMEDOUT|rate limit|503|502|504|unhandled.*promise|rejected.*reason"; then
      echo ""
      echo "  ⚠ Transient API error detected (attempt $retry/$MAX_RETRIES)"
      if [ "$retry" -lt "$MAX_RETRIES" ]; then
        echo "  Retrying in ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
        RETRY_DELAY=$((RETRY_DELAY * 2))  # Exponential backoff
        continue
      else
        echo "  ✗ Max retries exceeded. Saving error response."
        echo ""
        echo "═══════════════════════════════════════════════════════"
        echo "  CLAUDE API ERROR - Last Response:"
        echo "═══════════════════════════════════════════════════════"
        echo "$OUTPUT" | tail -50
        echo "═══════════════════════════════════════════════════════"
        record_metrics "failed" "API_ERROR" "Transient API error after $MAX_RETRIES retries"
        # Continue to next iteration instead of halting
        continue 2
      fi
    fi

    # Check for empty response
    if [ -z "$OUTPUT" ] || [ ${#OUTPUT} -lt 50 ]; then
      echo ""
      echo "  ⚠ Empty or minimal response (attempt $retry/$MAX_RETRIES)"
      if [ "$retry" -lt "$MAX_RETRIES" ]; then
        echo "  Retrying in ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
        RETRY_DELAY=$((RETRY_DELAY * 2))
        continue
      else
        echo "  ✗ Max retries exceeded for empty response."
        record_metrics "failed" "EMPTY_RESPONSE" "Empty response after $MAX_RETRIES retries"
        continue 2
      fi
    fi

    # Success - break out of retry loop
    CLAUDE_SUCCESS=true
    break
  done

  if [ "$CLAUDE_SUCCESS" != "true" ]; then
    echo "Iteration $i failed due to API issues. Continuing to next iteration..."
    sleep 2
    continue
  fi

  # Track last successful response for error reporting
  LAST_CLAUDE_OUTPUT="$OUTPUT"
  LAST_ITERATION="$i"

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

  # Check for completion signal FIRST - if all stories are done, no verification needed
  # Use anchored grep to avoid false positives when Claude mentions the tag in prose
  # (e.g., "I will not output <promise>COMPLETE</promise>")
  if echo "$OUTPUT" | grep -qE "^[[:space:]]*<promise>COMPLETE</promise>[[:space:]]*$"; then
    echo ""
    echo "Angainor completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    record_metrics "success" "COMPLETE" ""
    print_metrics_summary
    exit 0
  fi

  # Verify that verification was provided (enforcement of US-003 requirement)
  # Accept either <verification> XML blocks OR ✅ checkmarks as valid verification
  VERIFICATION_FAILED=false
  FAILURE_REASON=""

  # Check if any verification exists (XML format or checkmark format)
  # Note: grep -c outputs "0" AND exits 1 when no matches, so fallback must be outside $()
  HAS_XML_VERIFICATION=$(echo "$OUTPUT" | grep -c "<verification>") || HAS_XML_VERIFICATION=0
  HAS_CHECKMARK_VERIFICATION=$(echo "$OUTPUT" | grep -c "✅") || HAS_CHECKMARK_VERIFICATION=0

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

  # Extract skill candidates from iteration output (failures don't break loop)
  write_skill_candidate "$OUTPUT" "$STORY_ID" || true

  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Angainor reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
print_metrics_summary
exit 1
