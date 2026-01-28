# Angainor

**Autonomous AI Agent Loop for Claude Code**

Angainor is an autonomous AI agent loop that executes Product Requirements Documents (PRDs) or pursues measurable objectives by running Claude Code repeatedly until all tasks are complete. Each iteration spawns a fresh Claude instance with clean context, while memory persists through git history, structured files, and full transcript logs.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

## Key Features

- **Autonomous Execution**: Runs Claude Code in a loop, completing one user story per iteration
- **Memory Persistence**: Context survives across iterations via git commits, `progress.txt`, and `transcripts/`
- **Two Execution Modes**: PRD mode for defined tasks, Objective mode for goal-seeking experimentation
- **Verification Enforcement**: Requires explicit verification of acceptance criteria before marking stories complete
- **Automatic Skill Extraction**: Discovers and saves reusable learnings for future projects
- **Metrics Tracking**: Records iteration duration, success rates, and estimated token usage
- **Plateau Detection**: Automatically detects when objective progress stalls

## Quick Start

### Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed and authenticated
- Bash shell (Linux/macOS)
- `jq` for JSON processing

### Installation

**Option 1: One-line install (recommended)**

Install Angainor into your existing project:

```bash
# Install to current directory
curl -fsSL https://raw.githubusercontent.com/thepriceisright/angainor/main/install-angainor.sh | bash

# Install to a specific directory
curl -fsSL https://raw.githubusercontent.com/thepriceisright/angainor/main/install-angainor.sh | bash -s /path/to/project
```

This creates:
- `./angainor.sh` - Main entry point
- `./.angainor/` - Angainor internals (prompt templates, scripts)
- `./.mcp.json` - MCP config for headless browser testing
- `~/.claude/skills/{prd,angainor,objective,read-transcript}/` - Global skills

**Option 2: Clone repository**

For development or to explore the codebase:

```bash
git clone https://github.com/thepriceisright/angainor.git
cd angainor
```

### Running Angainor

**PRD Mode** (default) - Execute predefined user stories:

```bash
# Create your prd.json (see prd.json.example)
./angainor.sh              # Run up to 10 iterations
./angainor.sh 20           # Run up to 20 iterations
./angainor.sh --prd 15     # Explicit PRD mode
```

**Objective Mode** - Iterate toward a measurable goal:

```bash
# Create your objective.json (see objective.json.example)
./angainor.sh --objective      # Run up to 10 iterations
./angainor.sh --objective 15   # Run up to 15 iterations
```

**Debugging** - Troubleshoot empty responses or API issues:

```bash
./angainor.sh --verbose            # Show detailed API call info
./angainor.sh --debug              # Log everything to angainor-debug.log
./angainor.sh --debug=/tmp/log.txt # Custom debug log path
./angainor.sh --help               # Show all options
```

The verbose mode shows:
- Claude CLI version and command being executed
- Response lengths, exit codes, and stderr content
- Error patterns matched for API failures
- Diagnostic hints when metrics blocks are missing

## Execution Modes

### PRD Mode

Use when tasks are well-defined with clear acceptance criteria.

Each iteration:
1. Reads `prd.json` to find the next incomplete story (`passes: false`)
2. Reads `progress.txt` to learn from previous iterations
3. Implements the single user story
4. Runs quality checks (typecheck, lint, test)
5. Commits with message: `feat: [Story ID] - [Story Title]`
6. Outputs verification for each acceptance criterion
7. Updates `prd.json` to mark story complete
8. Appends learnings to `progress.txt`

When all stories have `passes: true`, outputs `<promise>COMPLETE</promise>` and exits.

### Objective Mode

Use when you have a measurable goal but the path to achieve it is unknown.

Each iteration:
1. Reads `objective.json` for the goal and current progress
2. Forms a hypothesis about what change might improve the metric
3. Implements a focused change
4. Runs the verification command to measure progress
5. Outputs a `<metrics>` block with current values
6. Commits with message: `exp: [Hypothesis] - [Result]`
7. Evaluates whether to continue, declare success, or signal termination

Termination signals:
- `SUCCESS` - Objective achieved (metrics satisfy success criteria)
- `IMPOSSIBLE` - Concrete evidence the objective cannot be achieved
- `PLATEAU` - Diminishing returns after exhausting approaches
- `MAX_ITERATIONS` - Iteration budget exhausted

## Configuration Files

### prd.json

Defines the project and user stories for PRD mode.

```json
{
  "project": "MyApp",
  "branchName": "angainor/task-priority",
  "description": "Task Priority System - Add priority levels to tasks",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add priority field to database",
      "description": "As a developer, I need to store task priority...",
      "acceptanceCriteria": [
        "Add priority column to tasks table",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "status": "pending",
      "attempts": 0,
      "notes": ""
    }
  ]
}
```

**Story Status Fields:**
- `passes`: boolean - whether the story is complete
- `status`: `"pending"` | `"blocked"` | `"passed"` - richer state tracking
- `attempts`: number - how many iterations attempted this story
- `blockedReason`: string - why a story is blocked (only on blocked stories)

### objective.json

Defines the measurable goal for Objective mode.

```json
{
  "objective": {
    "description": "Improve accuracy to 90% or higher",
    "context": "Current model achieves 78% accuracy...",
    "constraints": [
      "Must not increase inference time beyond 200ms",
      "Model size must stay under 500MB"
    ]
  },
  "verification": {
    "command": "python scripts/benchmark.py",
    "successCriteria": "accuracy >= 0.90",
    "metricsToTrack": ["accuracy", "precision", "recall"]
  },
  "stopping": {
    "maxIterations": 15,
    "plateauThreshold": {
      "metric": "accuracy",
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

## Memory Model

How context persists between iterations (each Claude instance starts fresh):

| Memory Type | Storage | Purpose |
|-------------|---------|---------|
| **Implementation** | Git commits | Code changes and history |
| **Learning** | `progress.txt` | Patterns, gotchas, codebase knowledge |
| **Task Status** | `prd.json` / `objective.json` | Which stories are done, metrics |
| **Deep Context** | `transcripts/` | Full iteration logs (searchable via skill) |

### progress.txt

Append-only log with learnings from each iteration. The `## Codebase Patterns` section at the top contains consolidated reusable patterns.

```markdown
## Codebase Patterns
- Use `sql<number>` template for aggregations
- Always use `IF NOT EXISTS` for migrations

---

## 2026-01-24 14:30 - US-001
Story: US-001
- Added priority column to tasks table
- Files changed: migrations/001_priority.sql, models/task.ts
- **Learnings for future iterations:**
  - The codebase uses Drizzle ORM for migrations
  - Run `npm run db:push` to apply migrations
---
```

## Story Sizing Rules

Each user story must be completable in ONE context window. A story is too large if ANY of:

1. **File Spread**: More than 5 files need modification
2. **System Boundaries**: Crosses more than 3 boundaries (DB + API + UI + external)
3. **Output Estimate**: Expected code exceeds ~300 lines

If a story is too large, split it into smaller stories with proper dependency ordering.

## Verification Enforcement

Angainor requires explicit verification of acceptance criteria. Each iteration must include either:

**XML Format:**
```xml
<verification>
Criterion: Typecheck passes
Evidence: Ran `npm run typecheck` - exit code 0, no errors
Conclusion: SATISFIED
</verification>
```

**Checkmark Format:**
```markdown
## Verification

✅ Typecheck passes - ran npm run typecheck, exit 0
✅ Unit tests pass - 42 tests passed, 0 failed
```

Iterations without verification evidence are **rejected** and don't count toward completion.

## Skills

Angainor includes Claude Code skills for workflow automation:

| Skill | Trigger | Purpose |
|-------|---------|---------|
| `/prd` | "create a prd", "plan this feature" | Generate PRDs with clarifying questions |
| `/angainor` | "convert this prd", "create prd.json" | Convert markdown PRDs to JSON format |
| `/objective` | "define an objective", "set up objective mode" | Interactive objective definition |
| `/read-transcript` | "search transcripts", "previous iteration" | Search deep context from past iterations |

## Metrics

Angainor writes iteration metrics to `metrics.json`:

```json
{
  "iterations": [
    {
      "timestamp": "2026-01-24-14-30-00",
      "duration_seconds": 180,
      "story_id": "US-001",
      "status": "success",
      "lines_changed": 45,
      "files_changed": 3,
      "estimated_tokens": 12500,
      "failure_reason": ""
    }
  ]
}
```

A human-readable summary prints on loop completion.

## Skill Extraction (Claudeception)

When an iteration discovers non-obvious, verified knowledge, it can extract reusable skills:

```
<<<SKILL_CANDIDATE>>>
category: error-resolutions
name: vitest-mock-import-order
description: Use when Vitest mock imports fail silently
content:
## Problem
Vitest mocks must be defined before importing the module under test...
## Solution
...
<<<END_SKILL_CANDIDATE>>>
```

**Quality gates** (all must pass):
- Non-obvious: Would a competent developer NOT know this?
- Reusable: Applies beyond this specific project?
- Verified: Tested and confirmed working?
- Specific trigger: Can you define exactly when to apply it?

**Categories:**
- `error-resolutions`: Fixes for cryptic errors, version conflicts
- `patterns`: Reusable code patterns, architectural approaches
- `workflows`: Multi-step processes, debugging strategies

Skills are saved to `~/.claude/skills/angainor-learnings/` and available across projects.

## Plugin Configuration

Angainor automatically manages plugin state for autonomous execution:

**Disabled during runs:**
- `automatic-code-review@claude-skillz` - Interferes with autonomous flow
- `explanatory-output-style@claude-plugins-official` - Adds unnecessary verbosity

Plugins are restored on exit (normal, error, or Ctrl+C).

## Browser Testing

For UI stories with "Verify in browser" criteria, use headless Playwright:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--browser", "chromium", "--headless", "--no-sandbox"]
    }
  }
}
```

Screenshots are saved to `screenshots/[story-id].png`.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All stories complete (PRD) or objective achieved (Objective) |
| 1 | Max iterations reached without completion |
| 2 | Objective declared IMPOSSIBLE |
| 3 | Objective PLATEAU detected |
| 4 | Objective MAX_ITERATIONS budget exhausted |

## Repository Structure

```
├── angainor.sh              # Main bash loop
├── prompt.md                # Agent instructions for PRD mode
├── objective-prompt.md      # Agent instructions for Objective mode
├── prd.json.example         # Example PRD format
├── objective.json.example   # Example Objective format
├── skills/                  # Claude Code skills
│   ├── prd/                 # Generate PRDs
│   ├── angainor/            # Convert PRDs to JSON
│   ├── objective/           # Define objectives
│   └── read-transcript/     # Search past iterations
├── flowchart/               # Interactive React Flow visualization
│   └── README.md            # Flowchart development instructions
└── CLAUDE.md                # Instructions for Claude Code
```

## Flowchart Visualization

An interactive React Flow diagram visualizes the Angainor loop:

```bash
cd flowchart
npm install
npm run dev    # Development server
npm run build  # Production build
```

## Best Practices

### Story Design
- Keep stories small: completable in one context window
- Order by dependencies: database → backend → frontend
- Include "Typecheck passes" in every story's acceptance criteria
- Add "Verify in browser" for UI changes

### Progress Logging
- Always append to `progress.txt`, never replace
- Consolidate reusable patterns in `## Codebase Patterns` section
- Document gotchas and non-obvious requirements

### Constraint Handling (Objective Mode)
- Constraints are non-negotiable
- Verify constraints before each change
- Document constraint violations immediately

### Failure Recovery
- After 3 failed attempts, mark story as BLOCKED
- Document failure hypotheses for future iterations
- Move on rather than waste context retrying

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run quality checks
5. Submit a pull request

## License

MIT License - see LICENSE file for details.

---

*Angainor: Breaking the chains of context limits, one iteration at a time.*
