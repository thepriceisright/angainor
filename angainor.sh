#!/bin/bash
# Angainor Wiggum - Long-running AI agent loop
# Usage: ./angainor.sh [max_iterations]              # PRD mode (default)
#        ./angainor.sh --prd [max_iterations]        # PRD mode (explicit)
#        ./angainor.sh --objective [max_iterations]  # Objective mode

set -e

# Parse command-line arguments
MODE="prd"  # Default mode
MAX_ITERATIONS=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --objective)
      MODE="objective"
      shift
      ;;
    --prd)
      MODE="prd"
      shift
      ;;
    *)
      # Assume it's the max_iterations number
      if [[ $1 =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      else
        echo "Error: Unknown argument '$1'"
        echo "Usage: ./angainor.sh [--prd|--objective] [max_iterations]"
        exit 1
      fi
      shift
      ;;
  esac
done

# Set default max iterations
MAX_ITERATIONS=${MAX_ITERATIONS:-10}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set config and prompt files based on mode
if [ "$MODE" = "objective" ]; then
  CONFIG_FILE="$SCRIPT_DIR/objective.json"
  PROMPT_FILE="$SCRIPT_DIR/objective-prompt.md"
  MODE_DISPLAY="OBJECTIVE"
else
  CONFIG_FILE="$SCRIPT_DIR/prd.json"
  PROMPT_FILE="$SCRIPT_DIR/prompt.md"
  MODE_DISPLAY="PRD"
fi

# Legacy aliases for backward compatibility (PRD mode uses PRD_FILE variable)
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"

# Validate config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  if [ "$MODE" = "objective" ]; then
    echo "Error: objective.json not found at $CONFIG_FILE"
    echo "Create an objective.json file or use --prd flag for PRD mode."
  else
    echo "Error: prd.json not found at $CONFIG_FILE"
    echo "Create a prd.json file or use --objective flag for Objective mode."
  fi
  exit 1
fi

# Validate prompt file exists
if [ ! -f "$PROMPT_FILE" ]; then
  if [ "$MODE" = "objective" ]; then
    echo "Error: objective-prompt.md not found at $PROMPT_FILE"
    echo "This file contains agent instructions for Objective mode."
  else
    echo "Error: prompt.md not found at $PROMPT_FILE"
    echo "This file contains agent instructions for PRD mode."
  fi
  exit 1
fi

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

# Extract metrics from agent output
# Arguments: output_text
# Returns: JSON string of metrics, or empty string if no metrics found
# Supports two formats:
#   1. JSON: <metrics>{"key": value, ...}</metrics>
#   2. Key-value: <metrics>key=value\nkey2=value2</metrics>
extract_metrics() {
  local output="$1"
  local metrics_block metrics_content

  # Check if metrics block exists
  if ! echo "$output" | grep -q "<metrics>"; then
    echo "  ⚠ No <metrics> block found in agent output" >&2
    echo ""  # Return empty string
    return 0  # Don't fail, just warn
  fi

  # Extract content between <metrics> and </metrics> tags
  metrics_block=$(echo "$output" | sed -n '/<metrics>/,/<\/metrics>/p')

  if [ -z "$metrics_block" ]; then
    echo "  ⚠ Malformed <metrics> block (missing end tag)" >&2
    echo ""
    return 0
  fi

  # Remove the XML tags to get just the content
  metrics_content=$(echo "$metrics_block" | sed '1d;$d' | tr -d '\r')

  if [ -z "$metrics_content" ]; then
    echo "  ⚠ Empty <metrics> block" >&2
    echo ""
    return 0
  fi

  # Detect format: JSON starts with { or [, otherwise assume key=value
  local first_char
  first_char=$(echo "$metrics_content" | sed 's/^[[:space:]]*//' | head -c 1)

  if [ "$first_char" = "{" ] || [ "$first_char" = "[" ]; then
    # JSON format - validate and pass through
    if echo "$metrics_content" | jq '.' > /dev/null 2>&1; then
      # Valid JSON - output it (compacted)
      echo "$metrics_content" | jq -c '.'
    else
      echo "  ⚠ Invalid JSON in <metrics> block" >&2
      echo ""
      return 0
    fi
  else
    # Key-value format: key=value (one per line)
    # Convert to JSON object
    local json_obj="{}"
    local line key value

    while IFS= read -r line; do
      # Skip empty lines
      [ -z "$line" ] && continue

      # Parse key=value
      if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        # Determine if value is numeric or string
        if [[ "$value" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
          # Numeric value - add without quotes
          json_obj=$(echo "$json_obj" | jq --arg k "$key" --argjson v "$value" '. + {($k): $v}')
        else
          # String value - add with quotes
          json_obj=$(echo "$json_obj" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}')
        fi
      else
        echo "  ⚠ Skipping malformed line in metrics: $line" >&2
      fi
    done <<< "$metrics_content"

    # Output the constructed JSON
    echo "$json_obj" | jq -c '.'
  fi
}

# Check for SUCCESS termination in Objective mode
# Arguments: output_text
# Returns: 0 if SUCCESS found (and state updated), 1 otherwise
check_objective_success() {
  local output="$1"

  # Only run in objective mode
  if [ "$MODE" != "objective" ]; then
    return 1
  fi

  # Check for <objective>SUCCESS</objective> signal
  if ! echo "$output" | grep -qE "^[[:space:]]*<objective>SUCCESS</objective>[[:space:]]*$"; then
    return 1
  fi

  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  OBJECTIVE ACHIEVED - SUCCESS"
  echo "═══════════════════════════════════════════════════════"

  # Update objective.json status to 'success'
  if [ -f "$CONFIG_FILE" ]; then
    jq '.status.state = "success"' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

    # Print final metrics
    local best_metrics iterations
    best_metrics=$(jq -c '.status.bestMetrics // {}' "$CONFIG_FILE")
    iterations=$(jq -r '.status.iterations // 0' "$CONFIG_FILE")

    echo "  Completed in $iterations iteration(s)"
    echo "  Final metrics: $best_metrics"
  fi

  echo "═══════════════════════════════════════════════════════"

  return 0
}

# Check for IMPOSSIBLE termination in Objective mode
# Arguments: output_text
# Returns: 0 if IMPOSSIBLE found (and state updated), 1 otherwise
check_objective_impossible() {
  local output="$1"

  # Only run in objective mode
  if [ "$MODE" != "objective" ]; then
    return 1
  fi

  # Check for <objective>IMPOSSIBLE</objective> signal
  if ! echo "$output" | grep -qE "^[[:space:]]*<objective>IMPOSSIBLE</objective>[[:space:]]*$"; then
    return 1
  fi

  # Extract reason from <reason>...</reason> block
  local reason=""
  if echo "$output" | grep -q "<reason>"; then
    reason=$(echo "$output" | sed -n '/<reason>/,/<\/reason>/p' | sed '1d;$d' | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  fi

  # Extract category from <category>...</category> block (technical|scope|resource)
  local category=""
  if echo "$output" | grep -q "<category>"; then
    category=$(echo "$output" | sed -n '/<category>/,/<\/category>/p' | sed '1d;$d' | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  fi

  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  OBJECTIVE IMPOSSIBLE"
  echo "═══════════════════════════════════════════════════════"

  # Print reason and category if available
  if [ -n "$category" ]; then
    echo "  Category: $category"
  fi
  if [ -n "$reason" ]; then
    echo "  Reason: $reason"
  fi

  # Update objective.json status to 'impossible' and store reason
  if [ -f "$CONFIG_FILE" ]; then
    local iterations
    iterations=$(jq -r '.status.iterations // 0' "$CONFIG_FILE")

    # Build jq expression based on available fields
    if [ -n "$reason" ]; then
      jq --arg reason "$reason" '.status.state = "impossible" | .status.impossibleReason = $reason' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
      jq '.status.state = "impossible"' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi

    echo "  Completed after $iterations iteration(s)"
  fi

  echo "═══════════════════════════════════════════════════════"

  return 0
}

# Update objective.json with iteration metrics (Objective mode only)
# Arguments: iteration_number metrics_json
# Returns: 0 on success, 1 on failure
update_objective_metrics() {
  local iteration="$1"
  local metrics_json="$2"

  # Only run in objective mode
  if [ "$MODE" != "objective" ]; then
    return 0
  fi

  # Ensure objective.json exists
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "  ⚠ Cannot update metrics: objective.json not found" >&2
    return 1
  fi

  # 1. Increment status.iterations
  # 2. Append to status.metricHistory with iteration number
  # 3. Update status.bestMetrics if current is better

  # Get the primary metric name for comparison
  local primary_metric
  primary_metric=$(jq -r '.stopping.plateauThreshold.metric // "accuracy"' "$CONFIG_FILE")

  # Create the history entry with iteration number and metrics
  local history_entry
  if [ -n "$metrics_json" ] && [ "$metrics_json" != "{}" ]; then
    history_entry=$(echo "$metrics_json" | jq --argjson iter "$iteration" '. + {"iteration": $iter}')
  else
    # No metrics - just record the iteration number
    history_entry="{\"iteration\": $iteration}"
  fi

  # Get current best metric value (or null if not set)
  local current_best
  current_best=$(jq -r --arg m "$primary_metric" '.status.bestMetrics[$m] // null' "$CONFIG_FILE")

  # Get new metric value from current metrics
  local new_value
  if [ -n "$metrics_json" ] && [ "$metrics_json" != "{}" ]; then
    new_value=$(echo "$metrics_json" | jq -r --arg m "$primary_metric" '.[$m] // null')
  else
    new_value="null"
  fi

  # Determine if we should update bestMetrics
  # Update if: current is null OR new value > current value
  local should_update_best="false"
  if [ "$new_value" != "null" ]; then
    if [ "$current_best" = "null" ]; then
      should_update_best="true"
    else
      # Compare numerically - new > current means improvement
      # Use awk for floating point comparison
      should_update_best=$(awk -v new="$new_value" -v cur="$current_best" 'BEGIN { print (new > cur) ? "true" : "false" }')
    fi
  fi

  # Build the jq update expression
  local jq_expr

  if [ "$should_update_best" = "true" ]; then
    # Update iterations, append to history, AND update bestMetrics
    jq_expr='.status.iterations = ($iter | tonumber) | .status.metricHistory += [$entry] | .status.bestMetrics = $metrics'
    jq --argjson iter "$iteration" \
       --argjson entry "$history_entry" \
       --argjson metrics "$metrics_json" \
       "$jq_expr" \
       "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  else
    # Update iterations and append to history only
    jq_expr='.status.iterations = ($iter | tonumber) | .status.metricHistory += [$entry]'
    jq --argjson iter "$iteration" \
       --argjson entry "$history_entry" \
       "$jq_expr" \
       "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  fi

  if [ $? -eq 0 ]; then
    echo "  ✓ Updated objective.json: iteration=$iteration, bestUpdated=$should_update_best"
    return 0
  else
    echo "  ⚠ Failed to update objective.json" >&2
    return 1
  fi
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

- Extracted: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
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

echo "Starting Angainor in $MODE_DISPLAY mode - Max iterations: $MAX_ITERATIONS"

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
    # Use gtimeout on macOS (from coreutils), timeout on Linux, or no timeout as fallback
    if command -v gtimeout &> /dev/null; then
      TIMEOUT_CMD="gtimeout --signal=KILL $CLAUDE_TIMEOUT"
    elif command -v timeout &> /dev/null; then
      TIMEOUT_CMD="timeout --signal=KILL $CLAUDE_TIMEOUT"
    else
      TIMEOUT_CMD=""  # No timeout available, run without
    fi

    if [ -n "$TIMEOUT_CMD" ]; then
      OUTPUT=$($TIMEOUT_CMD claude --dangerously-skip-permissions --print < "$PROMPT_FILE" 2>&1 | tee /dev/stderr "$TRANSCRIPT_FILE") || true
    else
      OUTPUT=$(claude --dangerously-skip-permissions --print < "$PROMPT_FILE" 2>&1 | tee /dev/stderr "$TRANSCRIPT_FILE") || true
    fi
    CLAUDE_EXIT_CODE=$?

    # Check for timeout (exit code 137 = killed by SIGKILL, 124 = timeout exit code)
    if [ -n "$TIMEOUT_CMD" ] && { [ "$CLAUDE_EXIT_CODE" -eq 137 ] || [ "$CLAUDE_EXIT_CODE" -eq 124 ]; }; then
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
  # Use sed instead of grep -P for macOS compatibility
  STORY_ID=$(echo "$OUTPUT" | grep -o 'feat: [A-Za-z]*-[0-9]*' | head -1 | sed 's/feat: //' || echo "")
  if [ -z "$STORY_ID" ]; then
    STORY_ID=$(echo "$OUTPUT" | grep -oE '[A-Z]+-[0-9]+' | head -1 || echo "unknown")
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

  # For Objective mode: extract metrics and update objective.json
  if [ "$MODE" = "objective" ]; then
    EXTRACTED_METRICS=$(extract_metrics "$OUTPUT")
    if [ -n "$EXTRACTED_METRICS" ]; then
      echo "  Extracted metrics: $EXTRACTED_METRICS"
    fi
    update_objective_metrics "$i" "$EXTRACTED_METRICS"

    # Check for SUCCESS termination signal
    if check_objective_success "$OUTPUT"; then
      record_metrics "success" "OBJECTIVE_SUCCESS" ""
      print_metrics_summary
      exit 0
    fi

    # Check for IMPOSSIBLE termination signal
    if check_objective_impossible "$OUTPUT"; then
      record_metrics "blocked" "OBJECTIVE_IMPOSSIBLE" "Agent determined objective is impossible"
      print_metrics_summary
      exit 2
    fi
  fi

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
