# Angainor Objective Mode Design

**Date:** 2025-01-23
**Status:** Approved
**Author:** Design collaboration

---

## Overview

Objective Mode extends Angainor with a second execution mode for open-ended exploration where the approach is unknown upfront. Unlike PRD mode (predefined task list), Objective Mode iterates toward a measurable goal, discovering the solution path through experimentation.

### When to Use Each Mode

| Mode | Use When |
|------|----------|
| **PRD Mode** | You know WHAT to build and can break it into discrete tasks |
| **Objective Mode** | You know the GOAL but not how to achieve it |

### Examples

- **PRD Mode:** "Add user authentication with login, signup, and password reset"
- **Objective Mode:** "Make the image classifier 90% accurate" or "Reduce API latency to under 100ms"

---

## Two-Phase Flow

```
┌─────────────────────────────────────────────────────────────┐
│ PHASE 1: PLANNING (Interactive)                             │
├─────────────────────────────────────────────────────────────┤
│ 1. User invokes /objective skill with goal description      │
│ 2. Skill asks clarifying questions (like /prd)              │
│ 3. Agent proposes:                                          │
│    - Verification approach (how to test success)            │
│    - Metrics to track (quantitative outputs)                │
│    - Stopping thresholds (plateau detection, max attempts)  │
│ 4. User approves or adjusts                                 │
│ 5. Skill writes objective.json + uses objective-prompt.md   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ PHASE 2: EXECUTION (Autonomous)                             │
├─────────────────────────────────────────────────────────────┤
│ ./angainor.sh --objective [max_iterations]                  │
│                                                             │
│ Each iteration:                                             │
│ 1. Read objective.json + progress.txt                       │
│ 2. Attempt to make progress toward objective                │
│ 3. Run verification command, capture metrics                │
│ 4. Record metrics in progress.txt and objective.json        │
│ 5. Evaluate: SUCCESS | CONTINUE | PLATEAU | IMPOSSIBLE      │
│ 6. Spawn fresh instance or terminate                        │
└─────────────────────────────────────────────────────────────┘
```

**Key difference from PRD mode:** No predefined task list. Each iteration decides what to try based on previous attempts and current state.

---

## objective.json Schema

```json
{
  "objective": {
    "description": "Make the image classifier achieve 90% accuracy on the test set",
    "context": "Classifier is in src/model.py, training script is train.py",
    "constraints": [
      "Do not modify the model architecture",
      "Do not use external pre-trained weights",
      "Training must complete in under 10 minutes"
    ]
  },

  "verification": {
    "command": "python evaluate.py --output-json",
    "successCriteria": "accuracy >= 0.90",
    "metricsToTrack": ["accuracy", "loss", "training_time"]
  },

  "stopping": {
    "maxIterations": 20,
    "plateauThreshold": {
      "metric": "accuracy",
      "minImprovement": 0.01,
      "windowSize": 3
    },
    "maxConsecutiveFailures": 3
  },

  "status": {
    "state": "running",
    "iterations": 5,
    "bestMetrics": { "accuracy": 0.82, "loss": 0.45 },
    "metricHistory": [
      { "iteration": 1, "accuracy": 0.65, "loss": 1.2 },
      { "iteration": 2, "accuracy": 0.72, "loss": 0.89 },
      { "iteration": 3, "accuracy": 0.78, "loss": 0.62 },
      { "iteration": 4, "accuracy": 0.81, "loss": 0.51 },
      { "iteration": 5, "accuracy": 0.82, "loss": 0.45 }
    ]
  }
}
```

### Field Reference

| Field | Purpose |
|-------|---------|
| `objective.description` | The goal in plain language |
| `objective.context` | Relevant codebase information (files, entry points) |
| `objective.constraints` | Boundaries the agent must respect |
| `verification.command` | Command to run; must output JSON with metrics |
| `verification.successCriteria` | Expression evaluated against metrics output |
| `verification.metricsToTrack` | Numeric values to record each iteration |
| `stopping.maxIterations` | Hard limit on iteration count |
| `stopping.plateauThreshold` | Detect diminishing returns (metric, min improvement, window) |
| `stopping.maxConsecutiveFailures` | Stop after N identical failures |
| `status.state` | Current state: `pending`, `running`, `success`, `plateau`, `impossible` |
| `status.metricHistory` | Tracked over iterations for plateau detection |
| `status.bestMetrics` | Best values achieved so far |

---

## Termination Conditions

The loop evaluates these conditions after each iteration, in priority order:

### 1. SUCCESS

```
verification.command exits 0 AND successCriteria evaluates true
```

Agent outputs:
```
<objective>SUCCESS</objective>
```

Example: `accuracy >= 0.90` and current accuracy is 0.91 → done.

### 2. IMPOSSIBLE

Agent outputs structured signal when it hits a fundamental blocker:

```
<objective>IMPOSSIBLE</objective>
<reason>The dataset only contains 50 samples - insufficient for 90% accuracy
without overfitting. Would need at least 500+ samples.</reason>
<category>resource</category>
```

Categories:
- `technical` - Can't be done with current technology/APIs
- `scope` - Requires changes outside agent's authority
- `resource` - Missing required resources (data, keys, permissions)

Loop terminates immediately, logs reason.

### 3. PLATEAU (Diminishing Returns)

Detected when ANY of:
- Last N iterations (`windowSize`) show < `minImprovement` in tracked metric
- Same verification error N times consecutively (`maxConsecutiveFailures`)
- No commits for 3+ iterations AND agent signals stuck

Agent outputs:
```
<objective>PLATEAU</objective>
<attempts>
- Iteration 8: Tried data augmentation, accuracy 0.82→0.83
- Iteration 9: Tried learning rate tuning, accuracy 0.83→0.83
- Iteration 10: Tried batch size changes, accuracy 0.83→0.82
</attempts>
<suggestion>Consider relaxing constraints or providing more training data</suggestion>
```

### 4. MAX_ITERATIONS

Hard stop at `stopping.maxIterations`. Not a failure - just a budget limit.

Agent outputs:
```
<objective>MAX_ITERATIONS</objective>
```

Loop exits with current best metrics displayed.

---

## /objective Skill

The skill guides users from vague goal → approved execution plan through conversation.

### Example Interaction

```
User: /objective make my API faster

Skill: I'll help you define a performance objective. A few questions:

1. Which API endpoint(s) should I focus on?
   A. All endpoints
   B. Specific endpoint (please specify)
   C. The slowest ones (I'll profile to find them)

User: B - the /api/search endpoint

Skill: 2. What's your target response time?
   A. Under 100ms (p95)
   B. Under 500ms (p95)
   C. 50% faster than current
   D. Other (please specify)

User: A

Skill: 3. What constraints should I respect?
   A. Don't change the database schema
   B. Don't add new dependencies
   C. Don't modify the API contract
   D. All of the above
   E. No constraints

User: D

Skill: 4. How should I measure performance?
   A. I have a benchmark script (please provide path)
   B. Use the test suite with timing
   C. Create a benchmark for me

User: C

Skill: Got it. Here's my proposed plan:

**Objective:** Reduce /api/search p95 response time to under 100ms

**Verification approach:**
- I'll create `scripts/benchmark-search.py` that runs 100 requests
- Output: JSON with p50, p95, p99 latencies
- Success: p95_ms < 100

**Metrics to track:** p50_ms, p95_ms, p99_ms, throughput_rps

**Stopping conditions:**
- Success: p95 < 100ms
- Plateau: <5% improvement over 3 iterations
- Max iterations: 15

**Constraints:**
- No schema changes
- No new dependencies
- No API contract changes

Does this look right? (yes / adjust: [what to change])

User: yes

Skill: [Writes objective.json to project root]

✅ Created objective.json

To start the optimization loop:
  ./angainor.sh --objective 15
```

### Skill Behavior

1. **Asks questions one at a time** with multiple choice options where possible
2. **Adapts questions** based on objective type (performance, accuracy, stability, etc.)
3. **Proposes verification approach** - may offer to create benchmark scripts
4. **Presents complete plan** for approval before writing any files
5. **Only writes objective.json** after explicit user approval

---

## objective-prompt.md (Agent Instructions)

Instructions given to each Claude instance in objective mode.

```markdown
# Objective Mode Instructions

You are an autonomous agent working toward a measurable objective.
Unlike task mode, there is NO predetermined solution - you must explore and experiment.

## Your Objective

**Goal:** {objective.description}

**Context:** {objective.context}

**Constraints:**
{objective.constraints as bullet list}

**Success Criteria:** {verification.successCriteria}

**Current Best:** {status.bestMetrics}

## Your Task This Iteration

1. Read `objective.json` - understand goal, constraints, current metrics
2. Read `progress.txt` - learn what's been tried, what worked/didn't
3. **Decide on ONE hypothesis** to test this iteration
4. **Implement it** (small, focused change)
5. **Run verification:** `{verification.command}`
6. **Record results** and learnings

## Key Principles

- **ONE hypothesis per iteration** - small changes are easier to attribute
- **Learn from history** - don't repeat failed approaches
- **Respect constraints** - violating them invalidates the solution
- **Quantify everything** - metrics drive decisions

## Verification Output

After implementing, run the verification command and report:

```
## Verification

Command: `{verification.command}`
Exit code: 0
Metrics:
  - accuracy: 0.84
  - loss: 0.42

Previous best: accuracy 0.82
Improvement: +0.02 ✅
```

## Termination Signals

**If you achieve success:**
```
<objective>SUCCESS</objective>
```

**If you hit a fundamental blocker:**
```
<objective>IMPOSSIBLE</objective>
<reason>[Specific explanation of why this cannot be achieved]</reason>
<category>[technical|scope|resource]</category>
```

**If you're stuck with no new ideas:**
```
<objective>PLATEAU</objective>
<attempts>[Summary of what you've tried]</attempts>
<suggestion>[What might help - more data, relaxed constraints, etc.]</suggestion>
```

## Progress Format

Append to progress.txt after each iteration:

```
## Iteration [N] - [Date]
Hypothesis: [What you tried and why]
Changes: [Files modified]
Result: [Metrics before → after]
Learning: [What this taught you for next iteration]
---
```

## What NOT To Do

- Don't try multiple unrelated changes in one iteration
- Don't repeat an approach that already failed
- Don't violate constraints even if it would improve metrics
- Don't claim success without running verification
- Don't give up without signaling PLATEAU or IMPOSSIBLE
```

---

## angainor.sh Modifications

### Invocation

```bash
# PRD mode (existing behavior, default)
./angainor.sh [max_iterations]
./angainor.sh --prd [max_iterations]

# Objective mode (new)
./angainor.sh --objective [max_iterations]
```

### Mode Detection

```bash
# Parse arguments
MODE="prd"  # default
while [[ $# -gt 0 ]]; do
  case $1 in
    --objective) MODE="objective"; shift ;;
    --prd) MODE="prd"; shift ;;
    *) MAX_ITERATIONS="$1"; shift ;;
  esac
done

# Select files based on mode
if [ "$MODE" = "objective" ]; then
  CONFIG_FILE="$SCRIPT_DIR/objective.json"
  PROMPT_FILE="$ANGAINOR_LIB_DIR/objective-prompt.md"
  echo "Starting Angainor in OBJECTIVE mode"
else
  CONFIG_FILE="$SCRIPT_DIR/prd.json"
  PROMPT_FILE="$ANGAINOR_LIB_DIR/prompt.md"
  echo "Starting Angainor in PRD mode"
fi

# Verify config exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: $CONFIG_FILE not found."
  [ "$MODE" = "objective" ] && echo "Run /objective skill first."
  [ "$MODE" = "prd" ] && echo "Run /angainor skill first."
  exit 1
fi
```

### Objective Mode Loop Additions

```bash
# After each iteration in objective mode:

# 1. Extract metrics from output (agent outputs <metrics> block)
extract_metrics() {
  local output="$1"
  echo "$output" | sed -n '/<metrics>/,/<\/metrics>/p' | sed 's/<[^>]*>//g'
}

# 2. Update objective.json with new metrics
update_objective_metrics() {
  local metrics="$1"
  local iteration="$2"

  jq --argjson m "$metrics" --argjson i "$iteration" '
    .status.iterations = $i |
    .status.metricHistory += [$m + {iteration: $i}] |
    .status.bestMetrics = (
      if ($m.accuracy // 0) > (.status.bestMetrics.accuracy // 0)
      then $m else .status.bestMetrics end
    )
  ' "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
}

# 3. Check for plateau via metrics
check_metric_plateau() {
  local window=$(jq -r '.stopping.plateauThreshold.windowSize' "$CONFIG_FILE")
  local min_improvement=$(jq -r '.stopping.plateauThreshold.minImprovement' "$CONFIG_FILE")
  local metric=$(jq -r '.stopping.plateauThreshold.metric' "$CONFIG_FILE")

  # Get last N metric values
  local values=$(jq -r ".status.metricHistory[-$window:][].$metric" "$CONFIG_FILE")

  # Calculate if improvement is below threshold
  # (implementation details omitted for brevity)
}

# 4. Termination checks
check_objective_termination() {
  local output="$1"

  if echo "$output" | grep -q "<objective>SUCCESS</objective>"; then
    echo "🎉 Objective achieved!"
    jq '.status.state = "success"' "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
    print_objective_summary
    return 0
  fi

  if echo "$output" | grep -q "<objective>IMPOSSIBLE</objective>"; then
    local reason=$(echo "$output" | sed -n '/<reason>/,/<\/reason>/p' | sed 's/<[^>]*>//g')
    echo "⛔ Objective impossible: $reason"
    jq '.status.state = "impossible"' "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
    return 0
  fi

  if echo "$output" | grep -q "<objective>PLATEAU</objective>"; then
    echo "📉 Diminishing returns detected"
    jq '.status.state = "plateau"' "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
    print_plateau_summary
    return 0
  fi

  # Check metric-based plateau even if agent didn't signal
  if check_metric_plateau; then
    echo "📉 Metric plateau detected (no improvement in last $window iterations)"
    jq '.status.state = "plateau"' "$CONFIG_FILE" > tmp.json && mv tmp.json "$CONFIG_FILE"
    print_plateau_summary
    return 0
  fi

  return 1  # Continue iterating
}
```

---

## File Structure

### New Files

```
skills/
└── objective/
    └── SKILL.md              # /objective skill - interactive planning

.angainor/ (or angainor-lib/)
└── objective-prompt.md       # Agent instructions for objective mode

project root (created at runtime):
└── objective.json            # Created by /objective skill after approval
```

### Modified Files

```
angainor.sh                   # Add --objective flag, mode detection,
                              # metric tracking, plateau detection

install-angainor.sh           # Include objective-prompt.md in downloads

CLAUDE.md                     # Document objective mode

README.md                     # Add objective mode documentation
```

---

## Implementation Plan

### Phase 1: Core Infrastructure
1. Create `objective.json` schema and validation
2. Create `objective-prompt.md` agent instructions
3. Modify `angainor.sh` for mode detection and flag parsing

### Phase 2: Objective Mode Loop
4. Add metric extraction from agent output
5. Add metric tracking in `objective.json`
6. Implement termination condition checks (SUCCESS, IMPOSSIBLE, PLATEAU)
7. Implement metric-based plateau detection

### Phase 3: /objective Skill
8. Create `/objective` skill with clarifying questions
9. Implement plan proposal and approval flow
10. Implement `objective.json` generation

### Phase 4: Installation & Documentation
11. Update `install-angainor.sh` to include new files
12. Update `CLAUDE.md` with objective mode documentation
13. Update `README.md` with usage examples

---

## Open Questions

1. **Metric output format:** Should verification commands be required to output JSON, or should we support parsing other formats?

2. **Benchmark creation:** Should the `/objective` skill be able to create benchmark scripts, or just reference existing ones?

3. **Hybrid mode:** Should there be a way to combine objective + task list (e.g., "achieve X by doing tasks Y, Z")?

4. **Metric visualization:** Should we add a summary visualization of metric history when the loop completes?

---

## Success Criteria

This design is successful when:

- [ ] User can run `/objective` to define a measurable goal
- [ ] `./angainor.sh --objective` iterates toward the goal
- [ ] Metrics are tracked and displayed over iterations
- [ ] Loop terminates appropriately on SUCCESS, IMPOSSIBLE, or PLATEAU
- [ ] Existing PRD mode continues to work unchanged
