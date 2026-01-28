#!/bin/bash
# Angainor Wiggum - Long-running AI agent loop
# Usage: ./angainor.sh [max_iterations]              # PRD mode (default)
#        ./angainor.sh --prd [max_iterations]        # PRD mode (explicit)
#        ./angainor.sh --objective [max_iterations]  # Objective mode

set -e

# Get script directory early (needed for --debug default path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse command-line arguments
MODE="prd"  # Default mode
MAX_ITERATIONS=""
VERBOSE=false
DEBUG_LOG=""
CLAUDE_TIMEOUT=""  # Will be set to default later if not specified
LIVE_OUTPUT=false  # Show Claude output in real-time
LLM_EXTRACTION=true  # Use LLM to extract data from unstructured output

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
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    --debug)
      # Enable debug logging to a file (implies verbose)
      VERBOSE=true
      DEBUG_LOG="$SCRIPT_DIR/angainor-debug.log"
      shift
      ;;
    --debug=*)
      # Enable debug logging to a specific file
      VERBOSE=true
      DEBUG_LOG="${1#*=}"
      shift
      ;;
    --timeout=*)
      # Set iteration timeout in seconds (default: 1800 for objective, 600 for PRD)
      CLAUDE_TIMEOUT="${1#*=}"
      shift
      ;;
    --no-timeout)
      # Disable timeout entirely
      CLAUDE_TIMEOUT="0"
      shift
      ;;
    --live)
      # Show Claude output in real-time (stream to terminal while capturing)
      LIVE_OUTPUT=true
      LIVE_OUTPUT_EXPLICIT=true
      shift
      ;;
    --no-live)
      # Force non-live mode (use --print, override objective mode default)
      LIVE_OUTPUT=false
      LIVE_OUTPUT_EXPLICIT=true
      shift
      ;;
    --no-llm-extraction)
      # Disable LLM-based extraction of metrics/priority from unstructured output
      LLM_EXTRACTION=false
      shift
      ;;
    --help|-h)
      echo "Usage: ./angainor.sh [OPTIONS] [max_iterations]"
      echo ""
      echo "Options:"
      echo "  --prd             Run in PRD mode (default)"
      echo "  --objective       Run in Objective mode"
      echo "  --timeout=SECS    Set iteration timeout (default: 1800s objective, 600s PRD)"
      echo "  --no-timeout      Disable iteration timeout entirely"
      echo "  --live            Stream Claude output in real-time (default for objective mode)"
      echo "  --no-live         Force non-streaming mode (use --print, may timeout on long tasks)"
      echo "  --verbose, -v     Enable verbose output for debugging"
      echo "  --debug           Enable debug logging to angainor-debug.log"
      echo "  --debug=FILE      Enable debug logging to specific file"
      echo "  --no-llm-extraction  Disable LLM-based extraction (requires OPENROUTER_API_KEY)"
      echo "  --help, -h        Show this help message"
      echo ""
      echo "Arguments:"
      echo "  max_iterations    Maximum iterations to run (default: 10)"
      exit 0
      ;;
    *)
      # Assume it's the max_iterations number
      if [[ $1 =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      else
        echo "Error: Unknown argument '$1'"
        echo "Usage: ./angainor.sh [--prd|--objective] [--verbose] [max_iterations]"
        echo "Use --help for more options."
        exit 1
      fi
      shift
      ;;
  esac
done

# Set default max iterations
MAX_ITERATIONS=${MAX_ITERATIONS:-10}

# Load .env file if it exists (for API keys)
if [ -f "$SCRIPT_DIR/.env" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.env"
elif [ -f ".env" ]; then
  # shellcheck disable=SC1091
  source ".env"
fi

# Check for required API key in objective mode with LLM extraction
if [ "$MODE" = "objective" ] && [ "$LLM_EXTRACTION" = true ]; then
  if [ -z "$OPENROUTER_API_KEY" ]; then
    echo "Error: OPENROUTER_API_KEY is required for objective mode."
    echo ""
    echo "LLM extraction uses OpenRouter to parse agent output into structured data."
    echo "This ensures metrics and priority directives are captured even when the"
    echo "agent doesn't output perfect XML tags."
    echo ""
    echo "To fix:"
    echo "  1. Create a .env file with: OPENROUTER_API_KEY=your-key-here"
    echo "  2. Or export OPENROUTER_API_KEY in your shell"
    echo "  3. Or use --no-llm-extraction to disable (not recommended)"
    echo ""
    echo "Get an API key at: https://openrouter.ai/keys"
    exit 1
  fi
fi

# Logging functions
log_verbose() {
  if [ "$VERBOSE" = true ]; then
    echo "[VERBOSE] $*"
  fi
  if [ -n "$DEBUG_LOG" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [VERBOSE] $*" >> "$DEBUG_LOG"
  fi
}

log_debug() {
  if [ -n "$DEBUG_LOG" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*" >> "$DEBUG_LOG"
  fi
}

log_error() {
  echo "[ERROR] $*" >&2
  if [ -n "$DEBUG_LOG" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >> "$DEBUG_LOG"
  fi
}

# Initialize debug log if enabled
if [ -n "$DEBUG_LOG" ]; then
  echo "" >> "$DEBUG_LOG"
  echo "═══════════════════════════════════════════════════════" >> "$DEBUG_LOG"
  echo "Angainor Debug Session Started: $(date)" >> "$DEBUG_LOG"
  echo "Mode: $MODE" >> "$DEBUG_LOG"
  echo "Max Iterations: $MAX_ITERATIONS" >> "$DEBUG_LOG"
  echo "Working Directory: $(pwd)" >> "$DEBUG_LOG"
  echo "═══════════════════════════════════════════════════════" >> "$DEBUG_LOG"
fi

# Set config and prompt files based on mode
if [ "$MODE" = "objective" ]; then
  CONFIG_FILE="$SCRIPT_DIR/objective.json"
  PROMPT_FILE="$SCRIPT_DIR/objective-prompt.md"
  MODE_DISPLAY="OBJECTIVE"
  # Objective mode defaults to live output because --print mode buffers ALL output
  # until Claude completes, which doesn't work for long-running benchmarks.
  # Users can override with --no-live if they really want --print mode.
  if [ "$LIVE_OUTPUT_EXPLICIT" != true ] && [ "$LIVE_OUTPUT" = false ]; then
    LIVE_OUTPUT=true
    LIVE_OUTPUT_AUTO=true  # Track that this was auto-enabled
  fi
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
CLAUDE_PID=""

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

# Interrupt handler - kill any running Claude process and clean up
interrupt_handler() {
  echo ""
  echo "  ⚠ Interrupted by user (Ctrl+C)"

  # Kill any running Claude process and its children
  if [ -n "$CLAUDE_PID" ] && kill -0 "$CLAUDE_PID" 2>/dev/null; then
    echo "  Terminating Claude process (PID: $CLAUDE_PID)..."
    # Kill the entire process group
    kill -TERM -"$CLAUDE_PID" 2>/dev/null || kill -TERM "$CLAUDE_PID" 2>/dev/null || true
    sleep 1
    # Force kill if still running
    kill -KILL -"$CLAUDE_PID" 2>/dev/null || kill -KILL "$CLAUDE_PID" 2>/dev/null || true
  fi

  # Also kill any orphaned claude processes from this script
  pkill -P $$ 2>/dev/null || true

  restore_plugins
  echo "  Angainor terminated."
  exit 130  # Standard exit code for Ctrl+C
}

# Register cleanup traps - EXIT covers normal exit and set -e failures
# SIGINT/SIGTERM cover Ctrl+C and kill commands
trap cleanup_on_exit EXIT
trap interrupt_handler INT TERM

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

# Extract structured data from agent output using LLM (OpenRouter)
# This is a fallback when XML parsing fails - extracts metrics and priority
# from natural language output
# Arguments: raw_output iteration_number
# Returns: JSON with metrics and priority_directive (or empty on failure)
extract_with_llm() {
  local output="$1"
  local iteration="$2"

  # Skip if LLM extraction is disabled
  if [ "$LLM_EXTRACTION" != true ]; then
    log_verbose "LLM extraction disabled"
    return 0
  fi

  # Check for API key
  if [ -z "$OPENROUTER_API_KEY" ]; then
    log_verbose "No OPENROUTER_API_KEY, skipping LLM extraction"
    return 0
  fi

  echo "  Using LLM to extract structured data from output..."

  # Truncate output to last 8000 chars to stay within context limits
  local truncated_output
  truncated_output=$(echo "$output" | tail -c 8000)

  # Build the extraction prompt
  local extraction_prompt
  extraction_prompt=$(cat <<'EXTRACTION_PROMPT'
Extract structured data from this AI agent iteration output. Output ONLY valid JSON, nothing else.

Required fields:
- metrics: object with numerical measurements found in output (accuracy, precision, recall, F1, etc.)
- iteration_complete: boolean - did the agent signal it finished? (look for COMPLETE, done, finished)
- priority_directive: object describing what the agent suggests trying next, with:
  - directive: specific actionable suggestion (or null if none)
  - reason: why this is important (or null)
  - approach_category: one of PARAMETER_TUNING, ALGORITHM_CHANGE, DATA_PIPELINE, ARCHITECTURE, ERROR_ANALYSIS, ASSUMPTION_CHALLENGE (or null)
  - suggestions: array of specific options to try (or empty array)

Rules:
- Only extract metrics that have explicit numerical values in the output
- Look for "Consider:", "Next:", "Try:", "Should try:" patterns for priority directives
- If unsure about a field, use null
- Output MUST be valid JSON only - no markdown, no explanation

Example output format:
{"metrics":{"fixture_type_accuracy":0.33},"iteration_complete":true,"priority_directive":{"directive":"Try X","reason":"Because Y","approach_category":"ALGORITHM_CHANGE","suggestions":["option1","option2"]}}
EXTRACTION_PROMPT
)

  # Create the full prompt with the agent output
  local full_prompt="$extraction_prompt

AGENT OUTPUT TO ANALYZE:
$truncated_output

JSON:"

  # Call OpenRouter API with Claude Haiku 4.5
  local response
  local http_code
  local temp_file
  temp_file=$(mktemp)

  # Use curl with error handling
  http_code=$(curl -s -w "%{http_code}" -o "$temp_file" \
    "https://openrouter.ai/api/v1/chat/completions" \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    -H "Content-Type: application/json" \
    -H "HTTP-Referer: https://github.com/anthropics/angainor" \
    -d "$(jq -n \
      --arg prompt "$full_prompt" \
      '{
        model: "anthropic/claude-3.5-haiku",
        max_tokens: 1024,
        temperature: 0,
        messages: [{role: "user", content: $prompt}]
      }')" 2>/dev/null) || http_code="000"

  if [ "$http_code" != "200" ]; then
    echo "  ⚠ LLM extraction failed (HTTP $http_code)" >&2
    rm -f "$temp_file"
    return 1
  fi

  # Extract the response content
  response=$(jq -r '.choices[0].message.content // empty' "$temp_file" 2>/dev/null)
  rm -f "$temp_file"

  if [ -z "$response" ]; then
    echo "  ⚠ LLM returned empty response" >&2
    return 1
  fi

  # Clean up the response - remove markdown code blocks if present
  response=$(echo "$response" | sed 's/^```json//g' | sed 's/^```//g' | sed 's/```$//g' | tr -d '\n' | sed 's/^[[:space:]]*//')

  # Validate it's valid JSON
  if ! echo "$response" | jq '.' >/dev/null 2>&1; then
    echo "  ⚠ LLM returned invalid JSON" >&2
    log_verbose "Invalid LLM response: $response"
    return 1
  fi

  echo "  ✓ LLM extraction successful"
  log_verbose "LLM extracted: $response"

  # Output the JSON
  echo "$response"
}

# Print comprehensive objective summary on completion
# Arguments: termination_reason (SUCCESS, IMPOSSIBLE, PLATEAU, MAX_ITERATIONS)
#            optional: additional_context (reason, category, attempts, suggestion, etc.)
# Reads from CONFIG_FILE for metrics and status
print_objective_summary() {
  local reason="$1"
  local context="$2"
  local category="$3"
  local attempts="$4"
  local suggestion="$5"

  # Only run in objective mode
  if [ "$MODE" != "objective" ]; then
    return 0
  fi

  # Ensure objective.json exists
  if [ ! -f "$CONFIG_FILE" ]; then
    return 0
  fi

  # Read status and metrics from objective.json
  local iterations best_metrics metric_history success_criteria
  local primary_metric window_size
  iterations=$(jq -r '.status.iterations // 0' "$CONFIG_FILE")
  best_metrics=$(jq -c '.status.bestMetrics // {}' "$CONFIG_FILE")
  metric_history=$(jq -c '.status.metricHistory // []' "$CONFIG_FILE")
  success_criteria=$(jq -r '.verification.successCriteria // ""' "$CONFIG_FILE")
  primary_metric=$(jq -r '.stopping.plateauThreshold.metric // "accuracy"' "$CONFIG_FILE")
  window_size=$(jq -r '.stopping.plateauThreshold.windowSize // 3' "$CONFIG_FILE")

  # Calculate metric trend from history
  local trend="unknown"
  local history_length
  history_length=$(echo "$metric_history" | jq 'length')

  if [ "$history_length" -ge 2 ]; then
    # Get first and last value of primary metric
    local first_val last_val
    first_val=$(echo "$metric_history" | jq -r --arg m "$primary_metric" '.[0][$m] // null')
    last_val=$(echo "$metric_history" | jq -r --arg m "$primary_metric" '.[-1][$m] // null')

    if [ "$first_val" != "null" ] && [ "$last_val" != "null" ]; then
      # Calculate trend using awk for floating point comparison
      local diff
      diff=$(awk -v last="$last_val" -v first="$first_val" 'BEGIN { printf "%.6f", last - first }')
      local is_improving is_declining
      is_improving=$(awk -v d="$diff" 'BEGIN { print (d > 0.01) ? "true" : "false" }')
      is_declining=$(awk -v d="$diff" 'BEGIN { print (d < -0.01) ? "true" : "false" }')

      if [ "$is_improving" = "true" ]; then
        trend="improving"
      elif [ "$is_declining" = "true" ]; then
        trend="declining"
      else
        trend="flat"
      fi
    fi
  fi

  echo ""
  echo "═══════════════════════════════════════════════════════"

  # Print header based on termination reason
  case "$reason" in
    SUCCESS)
      echo "  ✅ OBJECTIVE ACHIEVED - SUCCESS"
      ;;
    IMPOSSIBLE)
      echo "  ❌ OBJECTIVE IMPOSSIBLE"
      ;;
    PLATEAU)
      echo "  ⚠️ OBJECTIVE PLATEAU - Diminishing Returns"
      ;;
    MAX_ITERATIONS)
      echo "  ⏱️ OBJECTIVE MAX ITERATIONS - Budget Exhausted"
      ;;
    *)
      echo "  OBJECTIVE TERMINATED: $reason"
      ;;
  esac

  echo "═══════════════════════════════════════════════════════"
  echo ""

  # Common stats
  echo "  📊 Summary"
  echo "  ─────────────────────────────────────────────────────"
  echo "  Iterations completed: $iterations"
  echo "  Metric trend: $trend"
  echo "  Best metrics: $best_metrics"
  echo ""

  # Reason-specific details
  case "$reason" in
    SUCCESS)
      echo "  🎯 Success Criteria"
      echo "  ─────────────────────────────────────────────────────"
      if [ -n "$success_criteria" ]; then
        echo "  Criteria: $success_criteria"
        # Highlight which metrics met criteria by showing best metrics
        local tracked_metrics
        tracked_metrics=$(jq -r '.verification.metricsToTrack // [] | join(", ")' "$CONFIG_FILE")
        if [ -n "$tracked_metrics" ]; then
          echo "  Tracked metrics: $tracked_metrics"
        fi
        # Show final values vs criteria
        if [ "$best_metrics" != "{}" ]; then
          echo ""
          echo "  Final metric values:"
          echo "$best_metrics" | jq -r 'to_entries[] | "    \(.key): \(.value)"'
        fi
      fi
      ;;

    IMPOSSIBLE)
      echo "  ❌ Reason"
      echo "  ─────────────────────────────────────────────────────"
      if [ -n "$category" ]; then
        echo "  Category: $category"
      fi
      if [ -n "$context" ]; then
        echo "  Reason: $context"
      fi
      # Also show what was in objective.json impossibleReason if available
      local stored_reason
      stored_reason=$(jq -r '.status.impossibleReason // ""' "$CONFIG_FILE")
      if [ -n "$stored_reason" ] && [ "$stored_reason" != "$context" ]; then
        echo "  Details: $stored_reason"
      fi
      ;;

    PLATEAU)
      echo "  📉 Plateau Details"
      echo "  ─────────────────────────────────────────────────────"
      echo "  Primary metric: $primary_metric"
      echo "  Window size: $window_size iterations"

      # Show the stagnant window of iterations
      if [ "$history_length" -ge "$window_size" ]; then
        echo ""
        echo "  Stagnant iterations (last $window_size):"
        echo "$metric_history" | jq -r --arg m "$primary_metric" --argjson n "$window_size" \
          '.[-$n:][] | "    Iteration \(.iteration): \($m)=\(.[$m] // "N/A")"'
      fi

      # Show attempts and suggestion if available (agent-signaled plateau)
      if [ -n "$attempts" ]; then
        echo ""
        echo "  Attempts tried: $attempts"
      fi
      if [ -n "$suggestion" ]; then
        echo ""
        echo "  Suggestion: $suggestion"
      fi
      ;;

    MAX_ITERATIONS)
      echo "  ⏱️ Budget Details"
      echo "  ─────────────────────────────────────────────────────"
      local config_max cli_max
      config_max=$(jq -r '.stopping.maxIterations // 0' "$CONFIG_FILE")
      cli_max="$MAX_ITERATIONS"
      echo "  Config limit: $config_max"
      echo "  CLI limit: $cli_max"
      if [ "$config_max" -lt "$cli_max" ] && [ "$config_max" -gt 0 ]; then
        echo "  (Stopped at config limit)"
      else
        echo "  (Stopped at CLI limit)"
      fi

      # Show progress towards success criteria
      if [ -n "$success_criteria" ]; then
        echo ""
        echo "  Progress towards success criteria:"
        echo "    Criteria: $success_criteria"
        echo "    Best achieved: $best_metrics"
      fi
      ;;
  esac

  echo ""
  echo "═══════════════════════════════════════════════════════"
}

# Check for SUCCESS termination in Objective mode
# Arguments: output_text, metrics_json (optional - for validation)
# Returns: 0 if SUCCESS found (and state updated), 1 otherwise
check_objective_success() {
  local output="$1"
  local metrics="${2:-}"

  # Only run in objective mode
  if [ "$MODE" != "objective" ]; then
    return 1
  fi

  # IMPORTANT: Only check the TAIL of output for termination signals.
  # The prompt file (displayed at start in script mode) contains example SUCCESS tags
  # that would falsely match. Claude's actual response is at the END.
  # Use last 5000 chars which is enough for any reasonable response tail.
  local output_tail
  output_tail=$(echo "$output" | tail -c 5000)

  # Check for <objective>SUCCESS</objective> signal in the tail only
  if ! echo "$output_tail" | grep -qE "^[[:space:]]*<objective>SUCCESS</objective>[[:space:]]*$"; then
    return 1
  fi

  # Warn if SUCCESS is signaled without metrics
  if [ -z "$metrics" ] || [ "$metrics" = "{}" ] || [ "$metrics" = "null" ]; then
    echo ""
    echo "  ╔═══════════════════════════════════════════════════════"
    echo "  ║ ⚠ WARNING: SUCCESS signaled without valid metrics!"
    echo "  ╠═══════════════════════════════════════════════════════"
    echo "  ║ This may indicate Claude didn't run the benchmark or"
    echo "  ║ output was corrupted."
    echo "  ║"

    # Check if progress.txt was modified recently (within last 2 minutes)
    if [ -f "$PROGRESS_FILE" ]; then
      PROGRESS_MOD_TIME=$(stat -c %Y "$PROGRESS_FILE" 2>/dev/null || stat -f %m "$PROGRESS_FILE" 2>/dev/null || echo "0")
      CURRENT_TIME=$(date +%s)
      TIME_DIFF=$((CURRENT_TIME - PROGRESS_MOD_TIME))
      if [ "$TIME_DIFF" -lt 120 ]; then
        echo "  ║ progress.txt: Modified ${TIME_DIFF}s ago (OK)"
      else
        echo "  ║ progress.txt: NOT modified recently (${TIME_DIFF}s ago)"
        echo "  ║   → Claude may not have done any work"
      fi
    else
      echo "  ║ progress.txt: Does not exist"
    fi

    # Check transcript files
    echo "  ║"
    if [ -n "$TRANSCRIPT_FILE" ] && [ -f "$TRANSCRIPT_FILE" ]; then
      TRANS_SIZE=$(wc -c < "$TRANSCRIPT_FILE" 2>/dev/null | tr -d ' ')
      echo "  ║ Transcript: $TRANSCRIPT_FILE ($TRANS_SIZE bytes)"
    fi
    RAW_TRANSCRIPT="${TRANSCRIPT_FILE%.txt}.raw.txt"
    if [ -f "$RAW_TRANSCRIPT" ]; then
      RAW_SIZE=$(wc -c < "$RAW_TRANSCRIPT" 2>/dev/null | tr -d ' ')
      echo "  ║ Raw transcript: $RAW_TRANSCRIPT ($RAW_SIZE bytes)"
    fi
    echo "  ║"
    echo "  ║ Review the transcript files for what Claude actually output."
    echo "  ╚═══════════════════════════════════════════════════════"
    echo ""
  fi

  # Update objective.json status to 'success'
  if [ -f "$CONFIG_FILE" ]; then
    jq '.status.state = "success"' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  fi

  # Print comprehensive summary
  print_objective_summary "SUCCESS"

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

  # IMPORTANT: Only check the TAIL of output for termination signals.
  # The prompt file contains example tags that would falsely match.
  local output_tail
  output_tail=$(echo "$output" | tail -c 5000)

  # Check for <objective>IMPOSSIBLE</objective> signal in the tail only
  if ! echo "$output_tail" | grep -qE "^[[:space:]]*<objective>IMPOSSIBLE</objective>[[:space:]]*$"; then
    return 1
  fi

  # Extract reason from <reason>...</reason> block (use tail)
  local reason=""
  if echo "$output_tail" | grep -q "<reason>"; then
    reason=$(echo "$output_tail" | sed -n '/<reason>/,/<\/reason>/p' | sed '1d;$d' | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  fi

  # Extract category from <category>...</category> block (use tail)
  local category=""
  if echo "$output_tail" | grep -q "<category>"; then
    category=$(echo "$output_tail" | sed -n '/<category>/,/<\/category>/p' | sed '1d;$d' | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  fi

  # Update objective.json status to 'impossible' and store reason
  if [ -f "$CONFIG_FILE" ]; then
    # Build jq expression based on available fields
    if [ -n "$reason" ]; then
      jq --arg reason "$reason" '.status.state = "impossible" | .status.impossibleReason = $reason' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
      jq '.status.state = "impossible"' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
  fi

  # Print comprehensive summary (pass reason and category)
  print_objective_summary "IMPOSSIBLE" "$reason" "$category"

  return 0
}

# Check for PLATEAU termination in Objective mode (agent-signaled)
# Arguments: output_text
# Returns: 0 if PLATEAU found (and state updated), 1 otherwise
check_objective_plateau() {
  local output="$1"

  # Only run in objective mode
  if [ "$MODE" != "objective" ]; then
    return 1
  fi

  # IMPORTANT: Only check the TAIL of output for termination signals.
  # The prompt file contains example tags that would falsely match.
  local output_tail
  output_tail=$(echo "$output" | tail -c 5000)

  # Check for <objective>PLATEAU</objective> signal in the tail only
  if ! echo "$output_tail" | grep -qE "^[[:space:]]*<objective>PLATEAU</objective>[[:space:]]*$"; then
    return 1
  fi

  # Extract attempts from <attempts>...</attempts> block (use tail)
  local attempts=""
  if echo "$output_tail" | grep -q "<attempts>"; then
    attempts=$(echo "$output_tail" | sed -n '/<attempts>/,/<\/attempts>/p' | sed '1d;$d' | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  fi

  # Extract suggestion from <suggestion>...</suggestion> block (use tail)
  local suggestion=""
  if echo "$output_tail" | grep -q "<suggestion>"; then
    suggestion=$(echo "$output_tail" | sed -n '/<suggestion>/,/<\/suggestion>/p' | sed '1d;$d' | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  fi

  # Update objective.json status to 'plateau'
  if [ -f "$CONFIG_FILE" ]; then
    jq '.status.state = "plateau"' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  fi

  # Print comprehensive summary (pass attempts and suggestion for agent-signaled plateau)
  print_objective_summary "PLATEAU" "" "" "$attempts" "$suggestion"

  return 0
}

# Check for MAX_ITERATIONS termination in Objective mode (agent-signaled)
# Arguments: output_text
# Returns: 0 if MAX_ITERATIONS found (and state updated), 1 otherwise
check_objective_max_iterations() {
  local output="$1"

  # Only run in objective mode
  if [ "$MODE" != "objective" ]; then
    return 1
  fi

  # IMPORTANT: Only check the TAIL of output for termination signals.
  # The prompt file contains example tags that would falsely match.
  local output_tail
  output_tail=$(echo "$output" | tail -c 5000)

  # Check for <objective>MAX_ITERATIONS</objective> signal in the tail only
  if ! echo "$output_tail" | grep -qE "^[[:space:]]*<objective>MAX_ITERATIONS</objective>[[:space:]]*$"; then
    return 1
  fi

  # Update objective.json status to 'max_iterations'
  if [ -f "$CONFIG_FILE" ]; then
    jq '.status.state = "max_iterations"' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  fi

  # Print comprehensive summary
  print_objective_summary "MAX_ITERATIONS"

  return 0
}

# Check if iteration budget has been exhausted (automatic detection)
# Arguments: current_iteration
# Returns: 0 if max iterations reached (and state updated), 1 otherwise
check_max_iterations_budget() {
  local current_iteration="$1"

  # Only run in objective mode
  if [ "$MODE" != "objective" ]; then
    return 1
  fi

  # Ensure objective.json exists
  if [ ! -f "$CONFIG_FILE" ]; then
    return 1
  fi

  # Read maxIterations from objective.json stopping config
  local config_max_iterations
  config_max_iterations=$(jq -r '.stopping.maxIterations // 0' "$CONFIG_FILE")

  # If config doesn't specify maxIterations (0 or empty), don't trigger
  if [ "$config_max_iterations" -eq 0 ]; then
    return 1
  fi

  # Use the lower of: config maxIterations OR CLI MAX_ITERATIONS
  local effective_max
  if [ "$config_max_iterations" -lt "$MAX_ITERATIONS" ]; then
    effective_max="$config_max_iterations"
  else
    effective_max="$MAX_ITERATIONS"
  fi

  # Check if we've reached the effective max
  if [ "$current_iteration" -lt "$effective_max" ]; then
    return 1
  fi

  # Max iterations reached - update state
  jq '.status.state = "max_iterations"' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

  # Print comprehensive summary
  print_objective_summary "MAX_ITERATIONS"

  return 0
}

# Check for metric-based plateau (automatic detection from metric history)
# Arguments: none (reads from CONFIG_FILE)
# Returns: 0 if plateau detected (and state updated), 1 otherwise
check_metric_plateau() {
  # Only run in objective mode
  if [ "$MODE" != "objective" ]; then
    return 1
  fi

  # Ensure objective.json exists
  if [ ! -f "$CONFIG_FILE" ]; then
    return 1
  fi

  # Read plateau threshold config
  local metric min_improvement window_size
  metric=$(jq -r '.stopping.plateauThreshold.metric // "accuracy"' "$CONFIG_FILE")
  min_improvement=$(jq -r '.stopping.plateauThreshold.minImprovement // 0.01' "$CONFIG_FILE")
  window_size=$(jq -r '.stopping.plateauThreshold.windowSize // 3' "$CONFIG_FILE")

  # Get the metric history array length
  local history_length
  history_length=$(jq '.status.metricHistory | length' "$CONFIG_FILE")

  # Only trigger after at least windowSize iterations exist
  if [ "$history_length" -lt "$window_size" ]; then
    return 1
  fi

  # Extract the last windowSize values of the tracked metric
  # Calculate improvement: max - min across the window
  local window_values improvement
  window_values=$(jq -r --arg m "$metric" --argjson n "$window_size" \
    '[.status.metricHistory[-$n:][] | .[$m] // null | select(. != null)]' "$CONFIG_FILE")

  # Count valid values in window
  local valid_count
  valid_count=$(echo "$window_values" | jq 'length')

  # If we don't have enough valid metric values in the window, can't determine plateau
  if [ "$valid_count" -lt "$window_size" ]; then
    return 1
  fi

  # Calculate improvement: max - min across the window
  local max_val min_val
  max_val=$(echo "$window_values" | jq 'max')
  min_val=$(echo "$window_values" | jq 'min')

  # Improvement is max - min (the range of values in the window)
  improvement=$(awk -v max="$max_val" -v min="$min_val" 'BEGIN { printf "%.6f", max - min }')

  # Detect plateau when improvement < minImprovement
  local is_plateau
  is_plateau=$(awk -v imp="$improvement" -v thresh="$min_improvement" 'BEGIN { print (imp < thresh) ? "true" : "false" }')

  if [ "$is_plateau" != "true" ]; then
    return 1
  fi

  # Plateau detected - update state
  jq '.status.state = "plateau"' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

  # Print comprehensive summary (no attempts/suggestion for metric-based plateau)
  print_objective_summary "PLATEAU"

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
  local jq_error
  local jq_result

  echo "    iteration=$iteration, primary_metric=$primary_metric"
  echo "    current_best=$current_best, new_value=$new_value"
  echo "    should_update_best=$should_update_best"
  echo "    history_entry=$history_entry"

  if [ "$should_update_best" = "true" ]; then
    # Update iterations, append to history, AND update bestMetrics
    jq_expr='.status.iterations = ($iter | tonumber) | .status.metricHistory += [$entry] | .status.bestMetrics = $metrics'
    echo "    Running jq with bestMetrics update..."
    jq_error=$(jq --argjson iter "$iteration" \
       --argjson entry "$history_entry" \
       --argjson metrics "$metrics_json" \
       "$jq_expr" \
       "$CONFIG_FILE" 2>&1 > "$CONFIG_FILE.tmp")
    jq_result=$?
    if [ $jq_result -eq 0 ]; then
      mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
      echo "    jq error: $jq_error"
      rm -f "$CONFIG_FILE.tmp"
    fi
  else
    # Update iterations and append to history only
    jq_expr='.status.iterations = ($iter | tonumber) | .status.metricHistory += [$entry]'
    echo "    Running jq without bestMetrics update..."
    jq_error=$(jq --argjson iter "$iteration" \
       --argjson entry "$history_entry" \
       "$jq_expr" \
       "$CONFIG_FILE" 2>&1 > "$CONFIG_FILE.tmp")
    jq_result=$?
    if [ $jq_result -eq 0 ]; then
      mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
      echo "    jq error: $jq_error"
      rm -f "$CONFIG_FILE.tmp"
    fi
  fi

  if [ $jq_result -eq 0 ]; then
    echo "  ✓ Updated objective.json: iteration=$iteration, bestUpdated=$should_update_best"
    return 0
  else
    echo "  ⚠ Failed to update objective.json" >&2
    return 1
  fi
}

# Parse <set_priority> block from iteration output and write to objective.json
# Arguments: output_text iteration_number
# Returns: 0 if priority set (or none found), 1 on error
parse_and_set_priority() {
  local output="$1"
  local iteration="$2"

  # Only run in objective mode
  if [ "$MODE" != "objective" ]; then
    return 0
  fi

  # Check if <set_priority> block exists
  if ! echo "$output" | grep -q "<set_priority>"; then
    log_verbose "No <set_priority> block found"
    return 0
  fi

  echo "  Parsing priority directive from output..."

  # Extract ONLY THE LAST <set_priority> block (avoid template examples from prompt)
  # Use awk to find the last complete block
  local priority_block
  priority_block=$(echo "$output" | awk '
    /<set_priority>/ { capture=1; block="" }
    capture { block = block $0 "\n" }
    /<\/set_priority>/ { capture=0; last_block=block }
    END { printf "%s", last_block }
  ')

  if [ -z "$priority_block" ]; then
    echo "  ⚠ Malformed <set_priority> block"
    return 1
  fi

  # Helper function to extract content between XML tags (gets LAST occurrence)
  # Handles both same-line <tag>content</tag> and multi-line formats
  extract_last_tag_content() {
    local text="$1"
    local tag="$2"
    # Use grep -oP for Perl regex to extract content between tags, take last match
    echo "$text" | grep -oP "(?<=<${tag}>).*?(?=</${tag}>)" | tail -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
  }

  # Extract directive (required)
  local directive
  directive=$(extract_last_tag_content "$priority_block" "directive")
  if [ -z "$directive" ]; then
    echo "  ⚠ <set_priority> missing required <directive> field"
    return 1
  fi

  # Extract reason (required)
  local reason
  reason=$(extract_last_tag_content "$priority_block" "reason")
  if [ -z "$reason" ]; then
    echo "  ⚠ <set_priority> missing required <reason> field"
    return 1
  fi

  # Extract approachCategory (required)
  local approach_category
  approach_category=$(extract_last_tag_content "$priority_block" "approachCategory")
  if [ -z "$approach_category" ]; then
    echo "  ⚠ <set_priority> missing required <approachCategory> field"
    return 1
  fi

  # Validate approachCategory is one of the allowed values
  case "$approach_category" in
    PARAMETER_TUNING|ALGORITHM_CHANGE|DATA_PIPELINE|ARCHITECTURE|ERROR_ANALYSIS|ASSUMPTION_CHALLENGE)
      ;;
    *)
      echo "  ⚠ Invalid approachCategory: $approach_category"
      echo "    Must be one of: PARAMETER_TUNING, ALGORITHM_CHANGE, DATA_PIPELINE, ARCHITECTURE, ERROR_ANALYSIS, ASSUMPTION_CHALLENGE"
      return 1
      ;;
  esac

  # Extract suggestions (optional) - keep as string, may be JSON array
  local suggestions
  suggestions=$(extract_last_tag_content "$priority_block" "suggestions")
  # Default to empty array if not provided
  if [ -z "$suggestions" ]; then
    suggestions="[]"
  fi

  # Validate suggestions is valid JSON array (or make it one)
  if ! echo "$suggestions" | jq -e 'type == "array"' >/dev/null 2>&1; then
    # Try to parse as-is, if not array wrap it
    suggestions="[]"
  fi

  echo "    directive: $directive"
  echo "    reason: $reason"
  echo "    approachCategory: $approach_category"
  echo "    suggestions: $suggestions"

  # Write to objective.json
  local jq_error
  local jq_result
  jq_error=$(jq \
    --arg directive "$directive" \
    --arg reason "$reason" \
    --arg category "$approach_category" \
    --argjson suggestions "$suggestions" \
    --argjson iteration "$iteration" \
    '.status.nextIterationPriority = {
      directive: $directive,
      reason: $reason,
      approachCategory: $category,
      suggestions: $suggestions,
      setByIteration: $iteration
    }' \
    "$CONFIG_FILE" 2>&1 > "$CONFIG_FILE.tmp")
  jq_result=$?

  if [ $jq_result -eq 0 ]; then
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    echo "  ✓ Priority directive set for next iteration"
    return 0
  else
    echo "  ⚠ Failed to write priority to objective.json: $jq_error"
    rm -f "$CONFIG_FILE.tmp"
    return 1
  fi
}

# Clear priority from objective.json if iteration responded to it
# Arguments: output_text
# Returns: 0 always
clear_priority_if_responded() {
  local output="$1"

  # Only run in objective mode
  if [ "$MODE" != "objective" ]; then
    return 0
  fi

  # Check if there's an existing priority to clear
  local has_priority
  has_priority=$(jq -r '.status.nextIterationPriority // null' "$CONFIG_FILE")
  if [ "$has_priority" = "null" ]; then
    return 0
  fi

  # Check if output contains <priority_response> block
  if ! echo "$output" | grep -q "<priority_response>"; then
    echo "  ⚠ Priority directive exists but no <priority_response> in output"
    return 0
  fi

  echo "  Clearing priority directive (iteration responded)..."

  # Clear the priority
  local jq_error
  local jq_result
  jq_error=$(jq '.status.nextIterationPriority = null' "$CONFIG_FILE" 2>&1 > "$CONFIG_FILE.tmp")
  jq_result=$?

  if [ $jq_result -eq 0 ]; then
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    echo "  ✓ Priority directive cleared"
  else
    echo "  ⚠ Failed to clear priority: $jq_error"
    rm -f "$CONFIG_FILE.tmp"
  fi

  return 0
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

# Compute effective timeout for display
if [ -z "$CLAUDE_TIMEOUT" ]; then
  if [ "$MODE" = "objective" ]; then
    EFFECTIVE_TIMEOUT="1800s (30 min, objective default)"
  else
    EFFECTIVE_TIMEOUT="600s (10 min, PRD default)"
  fi
elif [ "$CLAUDE_TIMEOUT" = "0" ]; then
  EFFECTIVE_TIMEOUT="disabled"
else
  EFFECTIVE_TIMEOUT="${CLAUDE_TIMEOUT}s"
fi

echo "Starting Angainor in $MODE_DISPLAY mode - Max iterations: $MAX_ITERATIONS"
if [ "$LIVE_OUTPUT" = true ]; then
  if [ "$LIVE_OUTPUT_AUTO" = true ]; then
    echo "Capture mode: script (auto - --print buffers too long for objective mode)"
  else
    echo "Live output: ENABLED (Claude output will stream to terminal)"
  fi
fi
if [ "$VERBOSE" = true ]; then
  echo "Verbose mode: ENABLED"
  echo "Iteration timeout: $EFFECTIVE_TIMEOUT"
  if [ -n "$DEBUG_LOG" ]; then
    echo "Debug log: $DEBUG_LOG"
  fi
  log_verbose "Config file: $CONFIG_FILE"
  log_verbose "Prompt file: $PROMPT_FILE"
  log_verbose "Transcript dir: $TRANSCRIPT_DIR"

  # Diagnostic checks
  echo ""
  echo "Diagnostic checks:"

  # Check Claude CLI
  if command -v claude &> /dev/null; then
    CLAUDE_VERSION=$(claude --version 2>/dev/null | head -1 || echo "unknown")
    echo "  ✓ Claude CLI found: $CLAUDE_VERSION"
  else
    echo "  ✗ Claude CLI not found in PATH"
    log_error "Claude CLI not found"
  fi

  # Check config file
  if [ -f "$CONFIG_FILE" ]; then
    CONFIG_SIZE=$(wc -c < "$CONFIG_FILE" | tr -d ' ')
    echo "  ✓ Config file: $CONFIG_FILE ($CONFIG_SIZE bytes)"
    if ! jq '.' "$CONFIG_FILE" > /dev/null 2>&1; then
      echo "    ⚠ Warning: Config file is not valid JSON"
      log_error "Config file is not valid JSON"
    fi
  else
    echo "  ✗ Config file missing: $CONFIG_FILE"
  fi

  # Check prompt file
  if [ -f "$PROMPT_FILE" ]; then
    PROMPT_SIZE=$(wc -c < "$PROMPT_FILE" | tr -d ' ')
    PROMPT_LINES=$(wc -l < "$PROMPT_FILE" | tr -d ' ')
    echo "  ✓ Prompt file: $PROMPT_FILE ($PROMPT_SIZE bytes, $PROMPT_LINES lines)"
    # Warn if prompt file is very large (>50KB can cause issues)
    if [ "$PROMPT_SIZE" -gt 50000 ]; then
      echo "    ⚠ Warning: Prompt file is large (>50KB) - may cause slowness"
    fi
  else
    echo "  ✗ Prompt file missing: $PROMPT_FILE"
  fi

  # Quick Claude CLI test (using pipe, not redirect - redirect has known issues)
  echo "  Testing Claude CLI..."
  QUICK_TEST=$(echo "say OK" | timeout 30 claude --print 2>&1 | head -1 || echo "FAILED")
  if [ -n "$QUICK_TEST" ] && [ "$QUICK_TEST" != "FAILED" ]; then
    echo "  ✓ Claude CLI: Responsive (via pipe)"
  else
    echo "  ✗ Claude CLI: Not responding (check authentication with 'claude doctor')"
  fi

  # Check timeout command
  if command -v gtimeout &> /dev/null; then
    echo "  ✓ Timeout: gtimeout (macOS coreutils)"
  elif command -v timeout &> /dev/null; then
    echo "  ✓ Timeout: timeout (Linux)"
  else
    echo "  ⚠ Timeout: not available (no timeout protection)"
  fi

  echo ""
fi

# For objective mode, continue from where we left off (resume support)
# For PRD mode, always start at 1
START_ITERATION=1
if [ "$MODE" = "objective" ] && [ -f "$CONFIG_FILE" ]; then
  COMPLETED_ITERATIONS=$(jq -r '.status.iterations // 0' "$CONFIG_FILE")
  if [ "$COMPLETED_ITERATIONS" -gt 0 ]; then
    START_ITERATION=$((COMPLETED_ITERATIONS + 1))
    echo "Resuming from iteration $START_ITERATION (found $COMPLETED_ITERATIONS completed in objective.json)"
  fi
fi

# Calculate effective max (START + MAX_ITERATIONS - 1, capped by config if set)
EFFECTIVE_MAX=$((START_ITERATION + MAX_ITERATIONS - 1))
if [ "$MODE" = "objective" ] && [ -f "$CONFIG_FILE" ]; then
  CONFIG_MAX=$(jq -r '.stopping.maxIterations // 0' "$CONFIG_FILE")
  if [ "$CONFIG_MAX" -gt 0 ] && [ "$CONFIG_MAX" -lt "$EFFECTIVE_MAX" ]; then
    EFFECTIVE_MAX="$CONFIG_MAX"
    echo "Capped at iteration $EFFECTIVE_MAX (from objective.json stopping.maxIterations)"
  fi
fi

for i in $(seq $START_ITERATION $EFFECTIVE_MAX); do
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Angainor Iteration $i of $EFFECTIVE_MAX"
  echo "═══════════════════════════════════════════════════════"

  # Capture iteration start time for metrics and git checks
  ITERATION_START=$(date +%s)
  ITERATION_START_TIME=$(date -d "@$ITERATION_START" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$ITERATION_START" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')

  # Generate transcript filename
  TIMESTAMP=$(date +%Y-%m-%d-%H-%M-%S)
  TRANSCRIPT_FILE="$TRANSCRIPT_DIR/$TIMESTAMP-iteration-$i.txt"

  # For Objective mode: generate dynamic prompt with iteration context
  if [ "$MODE" = "objective" ]; then
    DYNAMIC_PROMPT_FILE=$(mktemp)

    # Extract current status from objective.json
    CURRENT_ITERATIONS=$(jq -r '.status.iterations // 0' "$CONFIG_FILE")
    BEST_METRICS=$(jq -c '.status.bestMetrics // {}' "$CONFIG_FILE")
    CURRENT_STATE=$(jq -r '.status.state // "pending"' "$CONFIG_FILE")
    SUCCESS_CRITERIA=$(jq -r '.verification.successCriteria // ""' "$CONFIG_FILE")

    # Check for priority directive from previous iteration
    PRIORITY_EXISTS=$(jq -r '.status.nextIterationPriority // null' "$CONFIG_FILE")
    PRIORITY_SECTION=""
    if [ "$PRIORITY_EXISTS" != "null" ]; then
      PRIORITY_DIRECTIVE=$(jq -r '.status.nextIterationPriority.directive // ""' "$CONFIG_FILE")
      PRIORITY_REASON=$(jq -r '.status.nextIterationPriority.reason // ""' "$CONFIG_FILE")
      PRIORITY_CATEGORY=$(jq -r '.status.nextIterationPriority.approachCategory // ""' "$CONFIG_FILE")
      PRIORITY_FROM=$(jq -r '.status.nextIterationPriority.setByIteration // "?"' "$CONFIG_FILE")
      PRIORITY_SUGGESTIONS=$(jq -c '.status.nextIterationPriority.suggestions // []' "$CONFIG_FILE")

      PRIORITY_SECTION="
## ⚠️ PRIORITY DIRECTIVE FROM ITERATION $PRIORITY_FROM (MANDATORY)

**YOU MUST ADDRESS THIS FIRST** before any other analysis.

**Directive:** $PRIORITY_DIRECTIVE
**Reason:** $PRIORITY_REASON
**Approach Category:** $PRIORITY_CATEGORY
**Suggestions:** $PRIORITY_SUGGESTIONS

**Required action:**
1. Output a \`<priority_response>\` block FIRST (before plateau check or hypothesis)
2. Either ATTEMPT the directive (it becomes your hypothesis) or SKIP with documented reason
3. Valid skip reasons: CONSTRAINT_VIOLATION, ALREADY_TRIED, SUPERSEDED

**You may NOT ignore this directive. You must explicitly respond to it.**

"
    fi

    # Create dynamic header with iteration context
    cat > "$DYNAMIC_PROMPT_FILE" << DYNAMIC_HEADER
# ⚠️ ITERATION $i - YOU MUST EXIT AFTER ONE EXPERIMENT

**THIS IS ITERATION $i.** Previous iterations completed: $CURRENT_ITERATIONS
**Best metrics so far:** $BEST_METRICS
**Success criteria:** $SUCCESS_CRITERIA
**Current state:** $CURRENT_STATE
$PRIORITY_SECTION
## YOUR ONE JOB THIS ITERATION:
1. Read progress.txt to see what was tried
2. Form ONE hypothesis
3. Implement ONE change
4. Run the benchmark
5. Output <metrics>{...}</metrics>
6. Output <iteration>COMPLETE</iteration>
7. **STOP IMMEDIATELY - DO NOT CONTINUE**

After outputting \`<iteration>COMPLETE</iteration>\`, angainor.sh will:
- Parse your metrics
- Update objective.json
- Spawn iteration $((i + 1)) with fresh context

**DO NOT run multiple experiments. DO NOT keep iterating. EXIT after ONE experiment.**

---

DYNAMIC_HEADER

    # Append the static prompt content
    cat "$PROMPT_FILE" >> "$DYNAMIC_PROMPT_FILE"

    # Use dynamic prompt for this iteration
    EFFECTIVE_PROMPT_FILE="$DYNAMIC_PROMPT_FILE"
    log_verbose "Generated dynamic prompt with iteration $i context"
  else
    EFFECTIVE_PROMPT_FILE="$PROMPT_FILE"
  fi

  # Run Claude with retry logic for transient API errors
  MAX_RETRIES=3
  RETRY_DELAY=5
  CLAUDE_SUCCESS=false
  ITERATION_SYNTHESIZED=false  # Flag for git-recovered iterations (skip verification)

  # Set timeout: use CLI value, or default based on mode
  # Objective mode gets longer default (30 min) since it often runs benchmarks
  if [ -z "$CLAUDE_TIMEOUT" ]; then
    if [ "$MODE" = "objective" ]; then
      ITERATION_TIMEOUT=3600  # 60 minutes for objective mode (ML benchmarks often take 30-60 min)
    else
      ITERATION_TIMEOUT=600   # 10 minutes for PRD mode
    fi
  elif [ "$CLAUDE_TIMEOUT" = "0" ]; then
    ITERATION_TIMEOUT=0  # No timeout
  else
    ITERATION_TIMEOUT="$CLAUDE_TIMEOUT"
  fi

  # Verbose: Log iteration details
  log_verbose "Starting iteration $i"
  log_verbose "Transcript file: $TRANSCRIPT_FILE"

  # Debug: Log prompt file info
  if [ -n "$DEBUG_LOG" ]; then
    log_debug "Prompt file size: $(wc -c < "$PROMPT_FILE" | tr -d ' ') bytes"
    log_debug "Prompt file lines: $(wc -l < "$PROMPT_FILE" | tr -d ' ') lines"
    log_debug "Config file ($CONFIG_FILE):"
    head -20 "$CONFIG_FILE" >> "$DEBUG_LOG" 2>&1 || echo "  (could not read)" >> "$DEBUG_LOG"
  fi

  for retry in $(seq 1 $MAX_RETRIES); do
    echo "  Calling Claude API (attempt $retry/$MAX_RETRIES)..."
    log_verbose "API call attempt $retry/$MAX_RETRIES at $(date '+%H:%M:%S')"

    # Run Claude with timeout protection to prevent hangs on crashed processes
    # Use gtimeout on macOS (from coreutils), timeout on Linux, or no timeout as fallback
    # ITERATION_TIMEOUT=0 means no timeout
    if [ "$ITERATION_TIMEOUT" = "0" ]; then
      TIMEOUT_CMD=""  # No timeout requested
    elif command -v gtimeout &> /dev/null; then
      TIMEOUT_CMD="gtimeout --signal=KILL $ITERATION_TIMEOUT"
    elif command -v timeout &> /dev/null; then
      TIMEOUT_CMD="timeout --signal=KILL $ITERATION_TIMEOUT"
    else
      TIMEOUT_CMD=""  # No timeout available, run without
    fi

    log_verbose "Timeout command: ${TIMEOUT_CMD:-'(none - no timeout)'}"
    log_verbose "Claude command: claude --dangerously-skip-permissions --print < $EFFECTIVE_PROMPT_FILE"

    # Capture stderr separately for debugging
    STDERR_FILE=$(mktemp)
    STDOUT_FILE=$(mktemp)

    log_verbose "Temp files: stdout=$STDOUT_FILE, stderr=$STDERR_FILE"

    # Run Claude and capture output to files for reliable capture
    # Run in background to capture PID for interrupt handling
    #
    # NOTE: --print mode has issues with very long sessions (>30min) where
    # "No messages returned" error occurs. Using --output-format json as fallback.
    if [ "$LIVE_OUTPUT" = true ]; then
      # Live mode: run Claude interactively (no --print) so output streams in real-time
      # Use 'script' to capture terminal output for later processing
      #
      # NOTE: Without --print, Claude runs interactively showing progress.
      # We use 'script' to capture the terminal output for later processing.
      # The captured output will include ANSI codes and spinner artifacts.
      #
      # IMPORTANT: We must send /exit after the prompt to make Claude exit cleanly.
      # Otherwise it waits for more input and the script hangs.

      # Only show live output banner if explicitly requested (not auto-enabled)
      if [ "$LIVE_OUTPUT_AUTO" != true ]; then
        echo ""
        echo "───────────────────────────────────────────────────────"
        echo "  LIVE OUTPUT (Claude is working...)"
        echo "  Press Ctrl+C to interrupt"
        echo "───────────────────────────────────────────────────────"
      fi

      # Run Claude interactively with script capturing output
      # -q = quiet, -e = return exit code, -c = command
      # We send /exit after the prompt to ensure Claude exits when done
      #
      # When auto-enabled (objective mode), suppress terminal output (> /dev/null)
      # When explicitly requested (--live), show output on terminal
      if [ "$LIVE_OUTPUT_AUTO" = true ]; then
        # Silent capture mode: use script for pseudo-TTY but don't show output
        if [ -n "$TIMEOUT_CMD" ]; then
          $TIMEOUT_CMD script -q -e -c "(cat '$EFFECTIVE_PROMPT_FILE'; echo ''; echo '/exit') | claude --dangerously-skip-permissions" "$STDOUT_FILE" > /dev/null 2> "$STDERR_FILE" &
          CLAUDE_PID=$!
        else
          script -q -e -c "(cat '$EFFECTIVE_PROMPT_FILE'; echo ''; echo '/exit') | claude --dangerously-skip-permissions" "$STDOUT_FILE" > /dev/null 2> "$STDERR_FILE" &
          CLAUDE_PID=$!
        fi
      else
        # Interactive mode: show output on terminal while capturing
        if [ -n "$TIMEOUT_CMD" ]; then
          $TIMEOUT_CMD script -q -e -c "(cat '$EFFECTIVE_PROMPT_FILE'; echo ''; echo '/exit') | claude --dangerously-skip-permissions" "$STDOUT_FILE" 2> "$STDERR_FILE" &
          CLAUDE_PID=$!
        else
          script -q -e -c "(cat '$EFFECTIVE_PROMPT_FILE'; echo ''; echo '/exit') | claude --dangerously-skip-permissions" "$STDOUT_FILE" 2> "$STDERR_FILE" &
          CLAUDE_PID=$!
        fi
      fi
    else
      # Normal mode: capture to file only (no terminal output)
      # Use stdbuf to disable output buffering if available (helps with capture issues)
      UNBUF_CMD=""
      if command -v stdbuf &> /dev/null; then
        UNBUF_CMD="stdbuf -oL -eL"
        log_verbose "Using stdbuf for unbuffered output"
      fi

      if [ -n "$TIMEOUT_CMD" ]; then
        if [ -n "$UNBUF_CMD" ]; then
          $TIMEOUT_CMD $UNBUF_CMD claude --dangerously-skip-permissions --print --output-format text < "$EFFECTIVE_PROMPT_FILE" > "$STDOUT_FILE" 2> "$STDERR_FILE" &
        else
          $TIMEOUT_CMD claude --dangerously-skip-permissions --print --output-format text < "$EFFECTIVE_PROMPT_FILE" > "$STDOUT_FILE" 2> "$STDERR_FILE" &
        fi
        CLAUDE_PID=$!
      else
        if [ -n "$UNBUF_CMD" ]; then
          $UNBUF_CMD claude --dangerously-skip-permissions --print --output-format text < "$EFFECTIVE_PROMPT_FILE" > "$STDOUT_FILE" 2> "$STDERR_FILE" &
        else
          claude --dangerously-skip-permissions --print --output-format text < "$EFFECTIVE_PROMPT_FILE" > "$STDOUT_FILE" 2> "$STDERR_FILE" &
        fi
        CLAUDE_PID=$!
      fi
    fi

    # Wait for Claude to complete (this allows interrupt signals to be caught)
    # For live mode, use a polling loop with a grace period to handle hanging processes
    log_verbose "Waiting for Claude process (PID: $CLAUDE_PID)"

    if [ "$LIVE_OUTPUT" = true ]; then
      # Polling wait with grace period for live mode
      # The iteration timeout ($ITERATION_TIMEOUT) handles the main work period
      # This grace period handles the case where Claude finished but script/pty hangs
      GRACE_PERIOD=30  # seconds to wait after process appears done
      POLL_INTERVAL=2
      GRACE_START=""
      LAST_SIZE=""

      while kill -0 "$CLAUDE_PID" 2>/dev/null; do
        # Check if stdout file has been stable (no changes) for a while
        if [ -f "$STDOUT_FILE" ]; then
          CURRENT_SIZE=$(wc -c < "$STDOUT_FILE" 2>/dev/null | tr -d ' ' || echo "0")

          if [ -n "$LAST_SIZE" ] && [ "$CURRENT_SIZE" = "$LAST_SIZE" ]; then
            # Output hasn't changed
            if [ -z "$GRACE_START" ]; then
              GRACE_START=$(date +%s)
              log_verbose "Output stabilized, starting grace period ($GRACE_PERIOD s)"
            else
              ELAPSED=$(($(date +%s) - GRACE_START))
              if [ $ELAPSED -ge $GRACE_PERIOD ]; then
                echo "  ⚠ Process appears hung (no output for ${GRACE_PERIOD}s), terminating..."
                kill -TERM "$CLAUDE_PID" 2>/dev/null || true
                sleep 2
                kill -KILL "$CLAUDE_PID" 2>/dev/null || true
                break
              fi
            fi
          else
            # Output changed, reset grace period
            GRACE_START=""
            LAST_SIZE="$CURRENT_SIZE"
          fi
        fi
        sleep $POLL_INTERVAL
      done
      wait "$CLAUDE_PID" 2>/dev/null || true
      CLAUDE_EXIT_CODE=$?
    else
      # Normal mode: simple wait
      wait "$CLAUDE_PID" 2>/dev/null || true
      CLAUDE_EXIT_CODE=$?
    fi

    log_verbose "Claude process completed with exit code: $CLAUDE_EXIT_CODE"
    CLAUDE_PID=""  # Clear PID after completion

    # Ensure filesystem buffers are flushed before reading output files
    # This prevents race conditions where wait() returns but buffers aren't written
    sync 2>/dev/null || true
    sleep 0.5  # Brief pause to ensure file writes complete

    # Show end of live output (only if explicitly requested, not auto-enabled)
    if [ "$LIVE_OUTPUT" = true ] && [ "$LIVE_OUTPUT_AUTO" != true ]; then
      echo ""
      echo "───────────────────────────────────────────────────────"
      echo "  END LIVE OUTPUT"
      echo "───────────────────────────────────────────────────────"
    fi

    # Read captured output from files
    if [ "$LIVE_OUTPUT" = true ]; then
      # Strip terminal artifacts from script output (interactive mode includes lots of formatting)
      # This includes:
      # - ANSI CSI sequences: \x1b[...m (colors), \x1b[...H (cursor), etc.
      # - ANSI OSC sequences: \x1b]...  (window titles, etc.)
      # - Other escape sequences: \x1b(B, \x1b>, etc.
      # - Control characters: backspace, carriage return, bells
      # - Spinner artifacts that get overwritten
      #
      # IMPORTANT: Cursor movement codes carry semantic meaning in Claude's output:
      # - Cursor-right (\x1b[1C, \x1b[2C) = SPACE between words
      # - Cursor-down (\x1b[1B, \x1b[2B) = NEWLINE
      # We must convert these to the appropriate characters, not just delete them.
      # Example: "I'll\x1b[1Cstart\x1b[1Bnext" should become "I'll start\nnext"
      OUTPUT=$(cat "$STDOUT_FILE" 2>/dev/null | \
        sed 's/\x1b\[[0-9]*C/ /g' | \
        sed 's/\x1b\[[0-9]*B/\n/g' | \
        sed 's/\x1b\[[0-9;]*[a-zA-DFGHJKSTfm]//g' | \
        sed 's/\x1b\][^\x07]*\x07//g' | \
        sed 's/\x1b[()][AB012]//g' | \
        sed 's/\x1b[>=]//g' | \
        tr -d '\r\x07\x08' | \
        sed 's/.*\r//g' | \
        sed 's/[●✓✗✶✻✽✢·⎿▌▐▛▜▝▘❯]//g' | \
        tr -s ' ' | \
        sed '/^[[:space:]]*$/d' || echo "")
    else
      OUTPUT=$(cat "$STDOUT_FILE" 2>/dev/null || echo "")
    fi
    STDERR_CONTENT=$(cat "$STDERR_FILE" 2>/dev/null || echo "")
    log_verbose "Output captured: ${#OUTPUT} chars, stderr: ${#STDERR_CONTENT} chars"

    # If stdout is empty but stderr has content, Claude may have output there
    if [ ${#OUTPUT} -eq 0 ] && [ ${#STDERR_CONTENT} -gt 100 ]; then
      log_verbose "Stdout empty but stderr has content - checking for output markers"
      # Check if stderr contains iteration markers (output went to wrong stream)
      if echo "$STDERR_CONTENT" | grep -q -E '<metrics>|<iteration>|<objective>'; then
        log_verbose "Found output markers in stderr, using stderr as output"
        OUTPUT="$STDERR_CONTENT"
      fi
    fi

    # Save both raw and processed output to transcript
    # Raw output goes to .raw.txt, processed goes to the regular transcript
    RAW_TRANSCRIPT_FILE="${TRANSCRIPT_FILE%.txt}.raw.txt"
    cat "$STDOUT_FILE" > "$RAW_TRANSCRIPT_FILE" 2>/dev/null || true
    echo "$OUTPUT" > "$TRANSCRIPT_FILE" 2>/dev/null || true

    # Debug: Show file sizes
    if [ -n "$DEBUG_LOG" ]; then
      STDOUT_SIZE=$(wc -c < "$STDOUT_FILE" 2>/dev/null | tr -d ' ' || echo "0")
      STDERR_SIZE=$(wc -c < "$STDERR_FILE" 2>/dev/null | tr -d ' ' || echo "0")
      log_debug "STDOUT file size: $STDOUT_SIZE bytes"
      log_debug "STDERR file size: $STDERR_SIZE bytes"
    fi

    rm -f "$STDERR_FILE" "$STDOUT_FILE"

    # Verbose: Log response details
    log_verbose "Claude exit code: $CLAUDE_EXIT_CODE"
    log_verbose "Response length: ${#OUTPUT} characters"
    log_verbose "Stderr length: ${#STDERR_CONTENT} characters"

    if [ -n "$DEBUG_LOG" ]; then
      log_debug "--- STDERR START ---"
      echo "$STDERR_CONTENT" | head -50 >> "$DEBUG_LOG"
      log_debug "--- STDERR END ---"
      if [ ${#OUTPUT} -lt 500 ]; then
        log_debug "--- STDOUT (full, < 500 chars) ---"
        echo "$OUTPUT" >> "$DEBUG_LOG"
        log_debug "--- STDOUT END ---"
      else
        log_debug "--- STDOUT (first 500 chars) ---"
        echo "${OUTPUT:0:500}" >> "$DEBUG_LOG"
        log_debug "--- STDOUT END ---"
      fi
    fi

    # Check for timeout (exit code 137 = killed by SIGKILL, 124 = timeout exit code)
    if [ -n "$TIMEOUT_CMD" ] && { [ "$CLAUDE_EXIT_CODE" -eq 137 ] || [ "$CLAUDE_EXIT_CODE" -eq 124 ]; }; then
      echo ""
      echo "  ⚠ Claude process timed out after ${ITERATION_TIMEOUT}s (attempt $retry/$MAX_RETRIES)"
      log_verbose "TIMEOUT: Exit code $CLAUDE_EXIT_CODE after ${ITERATION_TIMEOUT}s"
      log_verbose "TIMEOUT: stderr=$STDERR_CONTENT"
      if [ "$retry" -lt "$MAX_RETRIES" ]; then
        echo "  Retrying in ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
        RETRY_DELAY=$((RETRY_DELAY * 2))
        continue
      else
        echo "  ✗ Max retries exceeded due to timeouts."
        log_error "Max retries exceeded due to timeouts"
        record_metrics "failed" "TIMEOUT" "Process timed out after $MAX_RETRIES retries"
        continue 2
      fi
    fi

    # Check for transient API errors
    # Note: "No messages returned" is handled separately above (long session bug)
    if echo "$OUTPUT" | grep -qE "ECONNRESET|ETIMEDOUT|rate limit|503|502|504"; then
      MATCHED_ERROR=$(echo "$OUTPUT" | grep -oE "ECONNRESET|ETIMEDOUT|rate limit|503|502|504" | head -1)
      echo ""
      echo "  ⚠ Transient API error detected (attempt $retry/$MAX_RETRIES)"
      log_verbose "API ERROR: Matched pattern '$MATCHED_ERROR'"
      log_verbose "API ERROR: Full output length: ${#OUTPUT} chars"
      if [ "$VERBOSE" = true ]; then
        echo "  Error pattern: $MATCHED_ERROR"
        echo "  Response preview:"
        echo "$OUTPUT" | head -20 | sed 's/^/    /'
      fi
      if [ "$retry" -lt "$MAX_RETRIES" ]; then
        echo "  Retrying in ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
        RETRY_DELAY=$((RETRY_DELAY * 2))  # Exponential backoff
        continue
      else
        echo "  ✗ Max retries exceeded. Saving error response."
        log_error "Max retries exceeded for API error: $MATCHED_ERROR"
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
      log_verbose "EMPTY RESPONSE: Output length: ${#OUTPUT} chars (threshold: 50)"
      log_verbose "EMPTY RESPONSE: Exit code: $CLAUDE_EXIT_CODE"

      # For Objective mode: Check if work was done despite empty output (Claude CLI bug)
      if [ "$MODE" = "objective" ]; then
        echo "  Checking if work was done despite missing output..."

        # IMPORTANT: Wait for work to complete before checking git evidence
        # Claude may have spawned long-running processes that are still doing work
        # even though Claude's --print mode returned empty.
        #
        # Strategy: Poll for git activity. If new commits appear or files change,
        # work is still happening. Wait until activity stops or timeout.
        echo "  Monitoring for ongoing work (checking git activity)..."

        ACTIVITY_TIMEOUT=1800  # 30 minutes max total wait
        IDLE_THRESHOLD=60      # Consider work done after 60s of no changes
        POLL_INTERVAL=10

        ACTIVITY_START=$(date +%s)
        LAST_ACTIVITY=$(date +%s)
        LAST_COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "0")
        LAST_PROGRESS_HASH=$(md5sum "$PROGRESS_FILE" 2>/dev/null | cut -d' ' -f1 || echo "none")

        while true; do
          sleep $POLL_INTERVAL
          NOW=$(date +%s)
          ELAPSED=$((NOW - ACTIVITY_START))

          # Check for timeout
          if [ $ELAPSED -ge $ACTIVITY_TIMEOUT ]; then
            echo "  ⚠ Activity monitoring timeout after ${ACTIVITY_TIMEOUT}s"
            break
          fi

          # Check for new commits
          CURRENT_COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "0")
          CURRENT_PROGRESS_HASH=$(md5sum "$PROGRESS_FILE" 2>/dev/null | cut -d' ' -f1 || echo "none")

          if [ "$CURRENT_COMMIT_COUNT" != "$LAST_COMMIT_COUNT" ] || [ "$CURRENT_PROGRESS_HASH" != "$LAST_PROGRESS_HASH" ]; then
            echo "    Activity detected at ${ELAPSED}s (commits: $LAST_COMMIT_COUNT→$CURRENT_COMMIT_COUNT)"
            LAST_ACTIVITY=$NOW
            LAST_COMMIT_COUNT="$CURRENT_COMMIT_COUNT"
            LAST_PROGRESS_HASH="$CURRENT_PROGRESS_HASH"
          fi

          # Check if idle long enough
          IDLE_TIME=$((NOW - LAST_ACTIVITY))
          if [ $IDLE_TIME -ge $IDLE_THRESHOLD ]; then
            echo "  No activity for ${IDLE_TIME}s, assuming work complete."
            break
          fi
        done

        # Check for git commits made during this iteration
        RECENT_COMMITS=$(git log --oneline --since="$ITERATION_START_TIME" 2>/dev/null | head -5)

        # Check if progress.txt was modified
        PROGRESS_MODIFIED=""
        if [ -f "$PROGRESS_FILE" ]; then
          PROGRESS_MTIME=$(stat -c %Y "$PROGRESS_FILE" 2>/dev/null || stat -f %m "$PROGRESS_FILE" 2>/dev/null || echo "0")
          if [ "$PROGRESS_MTIME" -gt "$ITERATION_START" ]; then
            PROGRESS_MODIFIED="yes"
          fi
        fi

        if [ -n "$RECENT_COMMITS" ] || [ "$PROGRESS_MODIFIED" = "yes" ]; then
          echo ""
          echo "  ✓ WORK WAS DONE - Claude CLI failed to capture output"
          if [ -n "$RECENT_COMMITS" ]; then
            echo "  Git commits found:"
            echo "$RECENT_COMMITS" | sed 's/^/    /'
          fi
          if [ "$PROGRESS_MODIFIED" = "yes" ]; then
            echo "  progress.txt was updated"
          fi
          echo ""
          echo "  Synthesizing iteration completion..."

          # Try to extract actual metrics from progress.txt
          # Format in progress.txt: "**fixture_type_accuracy: 0.8571 → 0.9333 (+7.62%)**"
          # We want to extract the "after" value (0.9333)
          EXTRACTED_METRICS="{}"
          if [ -f "$PROGRESS_FILE" ]; then
            # Get the metrics we're tracking from objective.json
            METRICS_TO_TRACK=$(jq -r '.verification.metricsToTrack // [] | .[]' "$CONFIG_FILE" 2>/dev/null)

            # For each metric, try to find it in progress.txt
            for metric in $METRICS_TO_TRACK; do
              # Pattern: "metric_name: X → Y" - extract Y (the after value)
              # Also handle "metric_name: Y" without arrow
              METRIC_VALUE=$(tail -150 "$PROGRESS_FILE" | grep -oE "${metric}[^0-9]*[0-9]+\.[0-9]+ *→ *[0-9]+\.[0-9]+" | tail -1 | grep -oE '[0-9]+\.[0-9]+$' || echo "")
              if [ -z "$METRIC_VALUE" ]; then
                # Try pattern without arrow: "metric_name: Y"
                METRIC_VALUE=$(tail -150 "$PROGRESS_FILE" | grep -oE "${metric}[^0-9]*[0-9]+\.[0-9]+" | tail -1 | grep -oE '[0-9]+\.[0-9]+' || echo "")
              fi
              if [ -n "$METRIC_VALUE" ]; then
                EXTRACTED_METRICS=$(echo "$EXTRACTED_METRICS" | jq --arg k "$metric" --argjson v "$METRIC_VALUE" '. + {($k): $v}')
                echo "    Extracted $metric: $METRIC_VALUE"
              fi
            done
          fi

          # If we couldn't extract any metrics, use a placeholder
          if [ "$EXTRACTED_METRICS" = "{}" ]; then
            EXTRACTED_METRICS='{"note": "metrics not found in progress.txt - manual review needed"}'
            echo "    ⚠ Could not extract metrics from progress.txt"
          fi

          # Create synthetic output with actual metrics
          OUTPUT="[Transcript lost due to Claude CLI --print bug - but work was done]

## Evidence of work:
Commits: $RECENT_COMMITS
Progress updated: $PROGRESS_MODIFIED

<metrics>
$EXTRACTED_METRICS
</metrics>

<iteration>COMPLETE</iteration>"

          # Write synthetic output to transcript file (STDOUT_FILE was already deleted)
          echo "$OUTPUT" > "$TRANSCRIPT_FILE"
          CLAUDE_SUCCESS=true
          ITERATION_SYNTHESIZED=true  # Skip verification for git-recovered iterations
          log_verbose "Synthesized successful iteration from git evidence"
          break
        fi
      fi

      if [ "$VERBOSE" = true ]; then
        echo "  Output length: ${#OUTPUT} characters"
        echo "  Exit code: $CLAUDE_EXIT_CODE"
        if [ -n "$OUTPUT" ]; then
          echo "  Response content:"
          echo "$OUTPUT" | sed 's/^/    /'
        else
          echo "  Response content: (completely empty)"
        fi
        if [ -n "$STDERR_CONTENT" ]; then
          echo "  Stderr content:"
          echo "$STDERR_CONTENT" | head -20 | sed 's/^/    /'
        fi
      fi
      if [ "$retry" -lt "$MAX_RETRIES" ]; then
        echo "  Retrying in ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
        RETRY_DELAY=$((RETRY_DELAY * 2))
        continue
      else
        echo "  ✗ Max retries exceeded for empty response."
        log_error "Max retries exceeded for empty response (${#OUTPUT} chars)"
        if [ "$VERBOSE" = true ]; then
          echo ""
          echo "  Diagnostic info:"
          echo "    - Prompt file exists: $([ -f "$EFFECTIVE_PROMPT_FILE" ] && echo "yes" || echo "NO")"
          echo "    - Prompt file size: $(wc -c < "$EFFECTIVE_PROMPT_FILE" 2>/dev/null | tr -d ' ' || echo "N/A") bytes"
          echo "    - Config file exists: $([ -f "$CONFIG_FILE" ] && echo "yes" || echo "NO")"
          echo "    - Claude command: claude --dangerously-skip-permissions --print"
          echo "    - Check if Claude CLI is authenticated: run 'claude doctor'"
        fi
        record_metrics "failed" "EMPTY_RESPONSE" "Empty response after $MAX_RETRIES retries"
        continue 2
      fi
    fi

    # Success - break out of retry loop
    CLAUDE_SUCCESS=true
    log_verbose "API call successful on attempt $retry"
    log_verbose "Response length: ${#OUTPUT} characters"
    break
  done

  if [ "$CLAUDE_SUCCESS" != "true" ]; then
    echo "Iteration $i failed due to API issues. Continuing to next iteration..."
    log_verbose "Iteration $i failed - moving to next iteration"
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
  # Skip for synthesized iterations (recovered from git evidence)
  # Skip for objective mode (uses <metrics> + <iteration>COMPLETE</iteration> instead)
  VERIFICATION_FAILED=false
  FAILURE_REASON=""

  if [ "$ITERATION_SYNTHESIZED" = true ]; then
    log_verbose "Skipping verification check for synthesized iteration (git evidence)"
    echo "  ✓ Iteration recovered from git evidence - skipping verification"
  elif [ "$MODE" = "objective" ]; then
    # Objective mode uses <metrics> and <iteration>COMPLETE</iteration> signals, not <verification>
    log_verbose "Skipping PRD verification check for objective mode"
  else
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
  fi  # End of ITERATION_SYNTHESIZED check

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

  # For Objective mode: check for iteration boundary signal and extract metrics
  if [ "$MODE" = "objective" ]; then
    echo ""
    echo "  [Objective Mode Processing]"
    log_verbose "Output length: ${#OUTPUT} chars"

    # IMPORTANT: Use output tail for all tag checks to avoid matching prompt examples.
    # The prompt file (displayed at start in script mode) contains example tags.
    OUTPUT_TAIL=$(echo "$OUTPUT" | tail -c 5000)

    # Quick scan for key markers (in tail only - avoids matching prompt examples)
    HAS_SUCCESS=$(echo "$OUTPUT_TAIL" | grep -c "<objective>SUCCESS</objective>") || HAS_SUCCESS=0
    HAS_METRICS_TAG=$(echo "$OUTPUT_TAIL" | grep -c "<metrics>") || HAS_METRICS_TAG=0

    if [ ${#OUTPUT} -eq 0 ]; then
      echo "  ⚠ OUTPUT IS EMPTY! Claude returned no text."
    fi

    # Check for iteration completion signal (required to properly bound iterations)
    # Accept multiple formats (check TAIL only to avoid prompt examples):
    #   - <iteration>COMPLETE</iteration> (preferred XML format)
    #   - Just "COMPLETE" on its own line (Claude sometimes outputs this)
    #   - Any termination signal (SUCCESS, IMPOSSIBLE, PLATEAU)
    HAS_ITERATION_COMPLETE=$(echo "$OUTPUT_TAIL" | grep -cE "<iteration>COMPLETE</iteration>|<objective>(SUCCESS|IMPOSSIBLE|PLATEAU)</objective>|^[[:space:]]*COMPLETE[[:space:]]*$") || HAS_ITERATION_COMPLETE=0

    if [ "$HAS_ITERATION_COMPLETE" -eq 0 ]; then
      echo "  ⚠ ITERATION BOUNDARY MISSING"
      echo "    Agent did not output COMPLETE or termination signal."
      log_verbose "Missing iteration boundary signal"
    else
      echo "  ✓ Iteration boundary signal found"
    fi

    # Check for metrics block (in tail only)
    HAS_METRICS_BLOCK=$(echo "$OUTPUT_TAIL" | grep -c "<metrics>") || HAS_METRICS_BLOCK=0
    echo "  Has <metrics> block: $HAS_METRICS_BLOCK"

    echo "  Extracting metrics..."
    EXTRACTED_METRICS=$(extract_metrics "$OUTPUT_TAIL")
    LLM_EXTRACTED=""  # Will store LLM extraction result if needed

    if [ -n "$EXTRACTED_METRICS" ] && [ "$EXTRACTED_METRICS" != "{}" ]; then
      echo "  ✓ Extracted metrics from XML: $EXTRACTED_METRICS"
    else
      echo "  ⚠ No XML metrics found - trying LLM extraction..."

      # Fallback 1: Use LLM to extract from natural language
      LLM_EXTRACTED=$(extract_with_llm "$OUTPUT_TAIL" "$i" 2>&1)
      if [ -n "$LLM_EXTRACTED" ] && echo "$LLM_EXTRACTED" | jq '.' >/dev/null 2>&1; then
        # Extract metrics from LLM response
        LLM_METRICS=$(echo "$LLM_EXTRACTED" | jq -c '.metrics // {}')
        if [ -n "$LLM_METRICS" ] && [ "$LLM_METRICS" != "{}" ] && [ "$LLM_METRICS" != "null" ]; then
          EXTRACTED_METRICS="$LLM_METRICS"
          echo "  ✓ Extracted metrics via LLM: $EXTRACTED_METRICS"
        fi
      fi

      # Fallback 2: Extract metrics from progress.txt
      if [ -z "$EXTRACTED_METRICS" ] || [ "$EXTRACTED_METRICS" = "{}" ]; then
        echo "  ⚠ LLM extraction failed - trying progress.txt..."
        EXTRACTED_METRICS="{}"
        if [ -f "$PROGRESS_FILE" ]; then
          METRICS_TO_TRACK=$(jq -r '.verification.metricsToTrack // [] | .[]' "$CONFIG_FILE" 2>/dev/null)
          for metric in $METRICS_TO_TRACK; do
            # Pattern: "metric_name: X → Y" - extract Y (the after value)
            METRIC_VALUE=$(tail -150 "$PROGRESS_FILE" | grep -oE "${metric}[^0-9]*[0-9]+\.[0-9]+ *→ *[0-9]+\.[0-9]+" | tail -1 | grep -oE '[0-9]+\.[0-9]+$' || echo "")
            if [ -z "$METRIC_VALUE" ]; then
              # Try pattern without arrow: "metric_name: Y" or "metric_name=Y"
              METRIC_VALUE=$(tail -150 "$PROGRESS_FILE" | grep -oE "${metric}[^0-9]*[0-9]+\.[0-9]+" | tail -1 | grep -oE '[0-9]+\.[0-9]+' || echo "")
            fi
            if [ -n "$METRIC_VALUE" ]; then
              EXTRACTED_METRICS=$(echo "$EXTRACTED_METRICS" | jq --arg k "$metric" --argjson v "$METRIC_VALUE" '. + {($k): $v}')
              echo "    Found $metric: $METRIC_VALUE in progress.txt"
            fi
          done
        fi

        if [ "$EXTRACTED_METRICS" != "{}" ]; then
          echo "  ✓ Extracted metrics from progress.txt: $EXTRACTED_METRICS"
        else
          echo "  ⚠ Could not extract metrics from any source"
          # Show last 500 chars of output for debugging
          if [ ${#OUTPUT} -gt 0 ]; then
            echo "  Output tail (last 500 chars):"
            echo "$OUTPUT" | tail -c 500 | sed 's/^/    /'
          fi
        fi
      fi
    fi

    echo "  Updating objective.json..."
    if update_objective_metrics "$i" "$EXTRACTED_METRICS"; then
      echo "  ✓ objective.json updated"
    else
      echo "  ✗ Failed to update objective.json"
    fi

    # Handle priority directives:
    # 1. Clear existing priority if iteration responded to it
    # 2. Parse and set any new priority for next iteration (try XML first, then LLM)
    clear_priority_if_responded "$OUTPUT"
    parse_and_set_priority "$OUTPUT" "$i"

    # If XML priority parsing didn't find anything, try LLM extraction result
    if [ -n "$LLM_EXTRACTED" ] && echo "$LLM_EXTRACTED" | jq '.' >/dev/null 2>&1; then
      LLM_PRIORITY=$(echo "$LLM_EXTRACTED" | jq -c '.priority_directive // null')
      if [ "$LLM_PRIORITY" != "null" ]; then
        # Check if we already have a priority set
        EXISTING_PRIORITY=$(jq -r '.status.nextIterationPriority // null' "$CONFIG_FILE")
        if [ "$EXISTING_PRIORITY" = "null" ]; then
          # Extract fields from LLM priority
          LLM_DIRECTIVE=$(echo "$LLM_PRIORITY" | jq -r '.directive // empty')
          LLM_REASON=$(echo "$LLM_PRIORITY" | jq -r '.reason // empty')
          LLM_CATEGORY=$(echo "$LLM_PRIORITY" | jq -r '.approach_category // empty')
          LLM_SUGGESTIONS=$(echo "$LLM_PRIORITY" | jq -c '.suggestions // []')

          if [ -n "$LLM_DIRECTIVE" ]; then
            echo "  Setting priority from LLM extraction..."
            echo "    directive: $LLM_DIRECTIVE"
            jq --arg d "$LLM_DIRECTIVE" \
               --arg r "$LLM_REASON" \
               --arg c "$LLM_CATEGORY" \
               --argjson s "$LLM_SUGGESTIONS" \
               --argjson iter "$i" \
               '.status.nextIterationPriority = {
                 directive: $d,
                 reason: $r,
                 approachCategory: $c,
                 suggestions: $s,
                 setByIteration: $iter
               }' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            echo "  ✓ Priority directive set from LLM extraction"
          fi
        fi
      fi
    fi

    # Check for SUCCESS termination signal
    if check_objective_success "$OUTPUT" "$EXTRACTED_METRICS"; then
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

    # Check for PLATEAU termination signal (agent-signaled diminishing returns)
    if check_objective_plateau "$OUTPUT"; then
      record_metrics "blocked" "OBJECTIVE_PLATEAU" "Agent signaled diminishing returns"
      print_metrics_summary
      exit 3
    fi

    # Check for metric-based plateau (automatic detection from metric history)
    if check_metric_plateau; then
      record_metrics "blocked" "METRIC_PLATEAU" "No metric improvement in sliding window"
      print_metrics_summary
      exit 3
    fi

    # Check for MAX_ITERATIONS termination signal (agent-signaled)
    if check_objective_max_iterations "$OUTPUT"; then
      record_metrics "blocked" "OBJECTIVE_MAX_ITERATIONS" "Agent signaled iteration budget exhausted"
      print_metrics_summary
      exit 4
    fi

    # Check for automatic max iterations budget exhaustion
    if check_max_iterations_budget "$i"; then
      record_metrics "blocked" "MAX_ITERATIONS_BUDGET" "Reached iteration limit from config"
      print_metrics_summary
      exit 4
    fi

  fi

  # Extract skill candidates from iteration output (failures don't break loop)
  write_skill_candidate "$OUTPUT" "$STORY_ID" || true

  # Clean up dynamic prompt file if created
  if [ -n "$DYNAMIC_PROMPT_FILE" ] && [ -f "$DYNAMIC_PROMPT_FILE" ]; then
    rm -f "$DYNAMIC_PROMPT_FILE"
    DYNAMIC_PROMPT_FILE=""
  fi

  echo ""
  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Angainor completed iterations $START_ITERATION to $EFFECTIVE_MAX."
if [ "$MODE" = "objective" ]; then
  FINAL_ITERATIONS=$(jq -r '.status.iterations // 0' "$CONFIG_FILE" 2>/dev/null)
  echo "Total objective iterations completed: $FINAL_ITERATIONS"
fi
echo "Check $PROGRESS_FILE for status."
print_metrics_summary
exit 1
