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

Based on the answers, propose how success will be measured.

### Propose Verification Command

```markdown
## Proposed Verification

**Command:** `[the command to run]`

Examples:
- Performance: `python scripts/benchmark_latency.py --endpoint /api/process`
- Accuracy: `python scripts/evaluate_model.py --dataset validation`
- Coverage: `pytest --cov=src --cov-report=json`
- Quality: `./scripts/quality_metrics.sh`

**Does this command exist?**
- Yes, it exists and works
- No, please create it for me
- I need to modify an existing script
```

### Propose Success Criteria

```markdown
**Success Criteria:** `[metric expression]`

Examples:
- `accuracy >= 0.90`
- `latency_p99 < 100`
- `coverage >= 80`
- `error_rate < 0.01`

Is this target realistic? (Y/N/Adjust to: ___)
```

### Propose Metrics to Track

```markdown
**Metrics to Track:**
1. [Primary metric from success criteria]
2. [Related metric 1]
3. [Related metric 2]

Add or remove metrics? (List any changes)
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
