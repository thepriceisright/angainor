---
name: objective
description: "Create an objective.json for goal-driven autonomous iteration. Use when you want to optimize toward a measurable target (performance, accuracy, coverage) rather than implement a specific PRD. Triggers on: create objective, optimize for, improve accuracy, reduce latency, increase coverage, goal-driven."
---

# Objective Mode Setup

Create a measurable objective for autonomous goal-driven iteration. Unlike PRD mode (which executes a known plan), Objective mode explores approaches autonomously until a target is reached or diminishing returns are detected.

---

## The Job

1. Ask clarifying questions to understand what the user wants to optimize
2. Propose a verification approach (how to measure success)
3. Propose stopping conditions (when to stop iterating)
4. Generate `objective.json` after user approval

**Important:** Do NOT start implementing. Just create the objective.json.

---

## Step 1: Clarifying Questions

Ask questions to understand the optimization goal. Use lettered options where appropriate.

### Question 1: Objective Type

```
What kind of objective are you trying to achieve?

A. Performance - Reduce latency, improve throughput, decrease resource usage
B. Accuracy - Improve model accuracy, reduce errors, increase precision
C. Coverage - Increase test coverage, documentation coverage, feature coverage
D. Quality - Reduce bugs, improve code quality metrics, decrease technical debt
E. Other: [please specify your optimization goal]
```

### Question 2: Target Component

```
What component or system are you optimizing?

A. A specific endpoint or API
B. A machine learning model
C. The test suite
D. A specific module or subsystem
E. The entire application
F. Other: [please specify]
```

### Question 3: Current State

```
What is your current baseline? (This helps set realistic targets)

Please provide:
- Current metric value (e.g., "78% accuracy", "450ms latency")
- How it's measured (e.g., "pytest --cov", "benchmark script")
- Any known issues (e.g., "fails on edge cases", "slow on large inputs")
```

This question requires a free-form answer to capture specifics.

### Question 4: Target Value

```
What is your target? Choose one:

A. Specific target value: [e.g., "90% accuracy", "under 100ms"]
B. Percentage improvement: [e.g., "50% faster", "20% fewer errors"]
C. Best achievable within constraints (let the agent explore)
D. Match a benchmark: [e.g., "match competitor X", "industry standard"]
```

### Question 5: Constraints

```
What constraints must be respected? Select all that apply:

A. Performance bounds (e.g., "must not exceed 200ms latency")
B. Resource limits (e.g., "model under 500MB", "no GPU required")
C. API compatibility (e.g., "cannot change public interfaces")
D. No external dependencies (e.g., "cannot add new libraries")
E. Budget limits (e.g., "no paid services", "under $X")
F. Other: [please specify]
G. No constraints
```

For each selected constraint, ask for specific values.

---

## Adapting Questions by Objective Type

### For Performance Objectives (A)

Additional questions:
```
What is the performance bottleneck?

A. CPU-bound computation
B. I/O operations (disk, network)
C. Memory usage
D. External API calls
E. Unknown - needs profiling first
```

```
How do you measure performance?

A. I have an existing benchmark script
B. Use standard tools (e.g., pytest-benchmark, time command)
C. Create a benchmark for me
D. Measure via application logs/metrics
```

### For Accuracy Objectives (B)

Additional questions:
```
What type of accuracy problem?

A. Classification accuracy (correct predictions)
B. Regression accuracy (prediction error)
C. Detection accuracy (finding all relevant items)
D. Ranking accuracy (correct ordering)
E. Other: [please specify]
```

```
What evaluation data do you have?

A. Labeled validation/test set
B. Historical data with known outcomes
C. A/B test capability
D. Manual review process
E. Need to create evaluation data
```

### For Coverage Objectives (C)

Additional questions:
```
What kind of coverage?

A. Code coverage (lines/branches tested)
B. Feature coverage (functionality tested)
C. Documentation coverage
D. API endpoint coverage
E. Other: [please specify]
```

```
Current coverage tooling:

A. pytest-cov / coverage.py
B. jest --coverage
C. Other tool: [specify]
D. No coverage tool set up
```

### For Quality Objectives (D)

Additional questions:
```
What quality metrics matter most?

A. Bug count / error rate
B. Linting violations
C. Type coverage
D. Cyclomatic complexity
E. Technical debt score
F. Other: [please specify]
```

---

## Step 2: Verification Approach

Based on the answers, propose how success will be measured. **Adapt your proposals based on the objective type from Step 1.**

### Type-Specific Verification Commands

Propose a verification command tailored to the objective type:

#### For Performance Objectives (Type A)

```markdown
## Proposed Verification

**Command:** `python scripts/benchmark_performance.py --endpoint [endpoint] --iterations 100`

This command will:
- Run [N] iterations of the target operation
- Measure: latency (p50, p95, p99), throughput (req/sec), memory usage
- Output JSON metrics for tracking

**Does this benchmark script exist?**
A. Yes, I have an existing benchmark at: [path]
B. No, please create a benchmark script for me (Recommended)
C. I'll use a standard tool (pytest-benchmark, hyperfine, wrk)
D. I need to modify an existing script: [path]
```

#### For Accuracy Objectives (Type B)

```markdown
## Proposed Verification

**Command:** `python scripts/evaluate_model.py --dataset validation --output-json`

This command will:
- Load the model and validation dataset
- Run predictions on [N] samples
- Calculate: accuracy, precision, recall, F1-score
- Output JSON metrics for tracking

**Does this evaluation script exist?**
A. Yes, I have an existing evaluation at: [path]
B. No, please create an evaluation script for me (Recommended)
C. I'll use a standard tool (sklearn metrics, pytest with assertions)
D. I need to modify an existing script: [path]
```

#### For Coverage Objectives (Type C)

```markdown
## Proposed Verification

**Command:** `pytest --cov=[source_dir] --cov-report=json --cov-report=term`

This command will:
- Run the test suite with coverage tracking
- Measure: line coverage, branch coverage, missing lines
- Output coverage.json for metric extraction

**Is your coverage tooling configured?**
A. Yes, pytest-cov is set up and working
B. No, please help me set up coverage (Recommended)
C. I use a different coverage tool: [specify]
D. I need to configure coverage for specific modules
```

#### For Quality Objectives (Type D)

```markdown
## Proposed Verification

**Command:** `./scripts/quality_metrics.sh`

This script will aggregate:
- Linting violations (ruff, eslint)
- Type coverage (pyright, tsc)
- Complexity metrics (radon, complexity-report)

**Do you have quality metric tooling?**
A. Yes, I have existing quality scripts at: [path]
B. No, please create a quality metrics script for me (Recommended)
C. I want to use specific tools: [list tools]
D. I only care about: [specific metric]
```

### Offer to Create Benchmark Scripts

If user selects "create for me" (option B), acknowledge this:

```markdown
**Benchmark Creation Plan:**

I'll create `scripts/benchmark_[type].py` that:
1. [Specific action for this objective type]
2. Outputs JSON with metrics: [list metrics]
3. Can be run with: `python scripts/benchmark_[type].py`

This will be created as part of the first iteration.

Proceed with benchmark creation? (yes/adjust/no)
```

### Propose Success Criteria

Based on the objective type and target value from Step 1:

```markdown
**Success Criteria:** `[metric] [operator] [value]`

```

Type-specific examples:
- **Performance:** `latency_p99 < 100` (milliseconds)
- **Accuracy:** `accuracy >= 0.90` (0-1 scale)
- **Coverage:** `line_coverage >= 80` (percentage)
- **Quality:** `linting_violations < 10` (count)

```markdown
Is this target realistic based on your current state?

A. Yes, this target is achievable
B. Too aggressive - adjust to: [suggest lower target]
C. Too conservative - adjust to: [suggest higher target]
D. I want a different metric entirely: [specify]
```

### Propose Metrics to Track

Propose metrics relevant to the objective type. The primary metric must match the success criteria.

#### Performance Metrics (Type A)
```markdown
**Recommended Metrics to Track:**
1. `latency_p99` (primary) - 99th percentile response time
2. `latency_p50` - Median response time
3. `throughput` - Requests per second
4. `memory_mb` - Peak memory usage

Add, remove, or reorder? (List changes or 'OK')
```

#### Accuracy Metrics (Type B)
```markdown
**Recommended Metrics to Track:**
1. `accuracy` (primary) - Overall correct predictions
2. `precision` - True positives / predicted positives
3. `recall` - True positives / actual positives
4. `f1_score` - Harmonic mean of precision and recall

Add, remove, or reorder? (List changes or 'OK')
```

#### Coverage Metrics (Type C)
```markdown
**Recommended Metrics to Track:**
1. `line_coverage` (primary) - Percentage of lines covered
2. `branch_coverage` - Percentage of branches covered
3. `missing_lines` - Count of uncovered lines
4. `files_covered` - Number of files with any coverage

Add, remove, or reorder? (List changes or 'OK')
```

#### Quality Metrics (Type D)
```markdown
**Recommended Metrics to Track:**
1. `linting_violations` (primary) - Total lint errors
2. `type_coverage` - Percentage of typed code
3. `cyclomatic_complexity` - Average function complexity
4. `tech_debt_hours` - Estimated remediation time

Add, remove, or reorder? (List changes or 'OK')
```

### User Adjustment Summary

After proposing verification approach, present a summary the user can adjust:

```markdown
## Verification Proposal Summary

| Aspect | Proposed Value | Adjust? |
|--------|---------------|---------|
| Command | `[command]` | A. Keep / B. Change to: ___ |
| Create benchmark? | [Yes/No] | A. Keep / B. Change |
| Success criteria | `[expression]` | A. Keep / B. Change to: ___ |
| Metrics to track | [list] | A. Keep / B. Add: ___ / C. Remove: ___ |

Enter adjustments (e.g., "B. Change command to pytest") or 'OK' to proceed to Step 3.
```

---

## Step 3: Stopping Conditions

Propose when the loop should stop.

```markdown
## Proposed Stopping Conditions

**Max Iterations:** [10-20, based on complexity]
- Simple optimizations: 10 iterations
- Complex/exploratory: 15-20 iterations

**Plateau Detection:**
- Metric: [primary metric from success criteria]
- Minimum improvement: 0.01 (1%)
- Window size: 3 iterations

The loop stops if the primary metric improves less than 1% over 3 consecutive iterations.

**Consecutive Failures:** 3
The loop stops if 3 iterations in a row fail to produce valid results.

Adjust any of these? (Or 'OK' to proceed)
```

### Explaining Parameters in Plain Language

If the user seems unfamiliar:

```
**What these mean:**

- **Max Iterations**: The absolute maximum attempts. Think of this as your budget.
  After this many tries, the loop stops regardless of progress.

- **Plateau Detection**: How to detect "stuck" progress. If the metric barely
  improves for several attempts, it's probably time to try a different approach.

- **Consecutive Failures**: Safety stop for completely broken experiments.
  If nothing works 3 times in a row, something is fundamentally wrong.
```

---

## Step 4: Generate objective.json

Present the complete plan for approval:

```markdown
## Summary

**Objective:** [description]
**Target:** [success criteria]
**Verification:** `[command]`

**Constraints:**
- [constraint 1]
- [constraint 2]

**Stopping Conditions:**
- Max iterations: [N]
- Plateau: [metric] improving < [threshold] over [window] iterations
- Max failures: [N]

---

Ready to create objective.json? (yes/no/adjust)
```

Only after explicit approval ("yes", "y", "create it", etc.), write the file:

```json
{
  "objective": {
    "description": "[from answers]",
    "context": "[current state and known issues]",
    "constraints": [
      "[constraint 1]",
      "[constraint 2]"
    ]
  },
  "verification": {
    "command": "[verification command]",
    "successCriteria": "[metric expression]",
    "metricsToTrack": ["metric1", "metric2", "metric3"]
  },
  "stopping": {
    "maxIterations": [N],
    "plateauThreshold": {
      "metric": "[primary metric]",
      "minImprovement": 0.01,
      "windowSize": 3
    },
    "maxConsecutiveFailures": 3
  },
  "status": {
    "state": "pending",
    "iterations": 0,
    "bestMetrics": {},
    "metricHistory": []
  }
}
```

---

## After Approval

Print next steps:

```
objective.json created successfully!

Next steps:
1. Review the generated objective.json
2. Ensure the verification command works: [command]
3. Start autonomous iteration: ./angainor.sh --objective [max_iterations]

The agent will iterate autonomously, trying different approaches until:
- Success criteria are met
- Progress plateaus
- Max iterations reached
- The objective is determined impossible
```

---

## Checklist

Before saving objective.json:

- [ ] Asked about objective type, target, constraints
- [ ] Adapted follow-up questions based on objective type
- [ ] Proposed verification command (create if needed)
- [ ] Proposed realistic success criteria
- [ ] Proposed sensible stopping conditions
- [ ] Got explicit user approval
- [ ] Wrote objective.json with all fields populated
- [ ] Printed next steps
