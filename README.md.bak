# Angainor

**Autonomous AI agent loop for executing Product Requirements Documents (PRDs) with Claude Code.**

Angainor spawns fresh Claude instances iteratively, implementing user stories one at a time until complete. Memory persists through git commits, structured state files, and searchable transcripts. Each iteration is independent, making the system resilient and scalable.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

---

## Table of Contents

- [Why Angainor?](#why-angainor)
- [Quick Start](#quick-start)
- [How It Works](#how-it-works)
- [Objective Mode](#objective-mode)
- [Advanced Features](#advanced-features)
- [Key Concepts](#key-concepts)
- [Skills](#skills)
- [PRD Format](#prd-format)
- [Configuration](#configuration)
- [Debugging](#debugging)
- [Troubleshooting](#troubleshooting)

---

## Why Angainor?

Traditional AI coding faces these challenges:

| Problem | Angainor's Solution |
|---------|------------------|
| Context window limits | Fresh context per story, unlimited total capacity |
| Context pollution | Each iteration starts clean |
| Manual coordination | Autonomous progression through PRD |
| Quality regression | Automated quality gates before every commit |
| Lost implementation details | Searchable transcript logs |
| Knowledge silos | Automatic skill extraction for cross-project learning |

Angainor is ideal for: feature implementation, schema migrations, systematic refactoring, adding test coverage, and any multi-step task with clear acceptance criteria.

---

## Quick Start

### Installation

Install Angainor in any project with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/thepriceisright/angainor/main/install-angainor.sh | bash
```

Or install to a specific directory:

```bash
curl -fsSL https://raw.githubusercontent.com/thepriceisright/angainor/main/install-angainor.sh | bash -s /path/to/project
```

This installs:
- `.angainor/` directory with core files and skills
- `./angainor.sh` wrapper script
- Automatic `.claude/settings.json` configuration
- `.gitignore` entries for generated files

### Prerequisites

- [Claude Code CLI](https://claude.ai/code) installed and authenticated
- `jq` (JSON processor): `brew install jq` / `apt install jq`
- `git` (version control)

### Basic Usage

Angainor supports two modes: **PRD Mode** (default) for well-defined tasks, and **Objective Mode** for goal-driven exploration.

#### PRD Mode (default)

1. **Create a PRD** using the `/prd` skill:

```bash
claude
# In Claude session:
/prd
# Describe your feature, answer clarifying questions
```

2. **Convert to prd.json** using the `/angainor` skill:

```bash
claude
# In Claude session:
/angainor
# Point to your PRD markdown file
```

3. **Run Angainor**:

```bash
./angainor.sh              # Run with default 10 iterations
./angainor.sh 20           # Run with custom iteration limit
./angainor.sh --prd 20     # Explicit PRD mode
```

#### Objective Mode

1. **Define an objective** using the `/objective` skill:

```bash
claude
# In Claude session:
/objective
# Answer questions about your goal, metrics, and constraints
```

2. **Run Angainor in Objective Mode**:

```bash
./angainor.sh --objective          # Run with default max iterations
./angainor.sh --objective 15       # Run with custom iteration limit
```

See [Objective Mode](#objective-mode) section for detailed documentation.

#### Monitoring Progress

4. **Monitor progress**:
   - Watch console output for real-time status
   - Check `progress.txt` for cumulative learnings
   - View `transcripts/` for full iteration logs
   - See `metrics.json` for performance data

---

## How It Works

### The Angainor Loop

```
┌─────────────────────────────────────────────────────────┐
│  START: Configure Angainor Profile                      │
│  - Disable interfering plugins                          │
│  - Set up autonomous execution environment              │
└───────────────────┬─────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────┐
│  ITERATION N: Spawn Fresh Claude Instance               │
├─────────────────────────────────────────────────────────┤
│  1. Read prd.json → Find next story (passes=false)      │
│  2. Read progress.txt → Check Codebase Patterns first   │
│  3. Verify branch: checkout/create if needed            │
│  4. Implement ONLY that single story                    │
│  5. Run quality checks (typecheck, lint, test)          │
│  6. If checks fail → retry or mark blocked              │
│  7. Commit: feat: [Story ID] - [Story Title]            │
│  8. Output verification blocks (XML or ✅ checkmarks)   │
│  9. Update prd.json → Set passes=true                   │
│ 10. Append learnings to progress.txt                    │
│ 11. Save transcript to transcripts/[timestamp].txt      │
│ 12. Extract skills if quality gates pass                │
└───────────────────┬─────────────────────────────────────┘
                    │
                    ▼
              ┌─────────────┐
              │ All stories │
              │  complete?  │
              └──┬──────┬───┘
                 │      │
            YES  │      │ NO
                 │      │
                 ▼      └──────┐
    ┌────────────────────┐     │
    │ <promise>          │     │
    │   COMPLETE         │     │
    │ </promise>         │     │
    │                    │     │
    │ Print Metrics      │     │
    │ Restore Plugins    │     │
    │ EXIT SUCCESS       │     │
    └────────────────────┘     │
                               │
              ┌────────────────┘
              │
              ▼
    Spawn Next Claude Instance
    (Loop to ITERATION N+1)
```

### Memory Model

Angainor maintains context across stateless iterations through four memory layers:

| Layer | File | Purpose | Persistence |
|-------|------|---------|-------------|
| **Implementation Memory** | Git commits | Code changes and evolution | Permanent (git history) |
| **Learning Memory** | `progress.txt` | Patterns, gotchas, context | Append-only, archived on branch change |
| **Task Status Memory** | `prd.json` | Which stories are done, blocked | Updated each iteration |
| **Deep Context Memory** | `transcripts/*.txt` | Full conversation logs | Searchable via `/read-transcript` skill |

**Why this works:**
- Git commits show WHAT changed
- progress.txt explains WHY and documents learnings
- prd.json tracks WHERE we are
- transcripts provide deep HOW context when needed

---

## Objective Mode

Objective Mode is an alternative execution mode for **goal-driven exploration** when the approach is unknown upfront. Instead of executing predefined user stories, the agent iterates toward a measurable goal through experimentation.

### When to Use Objective Mode

| Use PRD Mode (default) | Use Objective Mode |
|------------------------|-------------------|
| Tasks are well-defined with clear acceptance criteria | Goal is measurable but approach is unknown |
| Implementation approach is known upfront | Requires experimentation to find solutions |
| Examples: Add feature X, Fix bug Y, Refactor module Z | Examples: Improve accuracy to 90%, Reduce latency to <100ms |

### Two-Phase Workflow

Objective Mode uses a **two-phase workflow**:

```
┌───────────────────────────────────────────────────────┐
│  PHASE 1: Interactive Planning                        │
│  Run: /objective skill in Claude Code                 │
├───────────────────────────────────────────────────────┤
│  1. Answer clarifying questions about your goal       │
│  2. Review proposed verification method               │
│  3. Adjust stopping conditions if needed              │
│  4. Approve → generates objective.json                │
└───────────────────┬───────────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────────────┐
│  PHASE 2: Autonomous Execution                        │
│  Run: ./angainor.sh --objective [max_iterations]      │
├───────────────────────────────────────────────────────┤
│  Loop until termination:                              │
│  1. Read objective.json and progress.txt              │
│  2. Form hypothesis based on current state            │
│  3. Implement and verify the hypothesis               │
│  4. Output metrics in <metrics> block                 │
│  5. Evaluate: improve, pivot, or terminate            │
│  6. Loop continues until stopping condition met       │
└───────────────────────────────────────────────────────┘
```

### Quick Start (Objective Mode)

**1. Define your objective** using the `/objective` skill:

```bash
claude
# In Claude session:
/objective
# Answer questions about your goal, metrics, and constraints
```

**2. Run Angainor in Objective Mode**:

```bash
./angainor.sh --objective          # Run with default max iterations
./angainor.sh --objective 15       # Run with custom iteration limit
```

**3. Monitor progress**:
- Watch console for iteration metrics and trend analysis
- Check `objective.json` for `status.metricHistory`
- Review `progress.txt` for experiment learnings

### Termination Conditions

Objective Mode has four termination conditions:

| Signal | Exit Code | Meaning |
|--------|-----------|---------|
| `SUCCESS` | 0 | Objective achieved - `successCriteria` expression is true |
| `IMPOSSIBLE` | 2 | Agent determines objective cannot be achieved (with evidence) |
| `PLATEAU` | 3 | Diminishing returns - no improvement across window of iterations |
| `MAX_ITERATIONS` | 4 | Iteration budget exhausted without success |

**Example termination output:**

```
═══════════════════════════════════════════════════════
  OBJECTIVE SUCCESS - Goal Achieved! 🎉
═══════════════════════════════════════════════════════
  Iterations:    7
  Best Metrics:  accuracy: 0.912, f1_score: 0.895
  Trend:         Improving (+0.132 from start)

  Success Criteria Met:
    accuracy >= 0.90 ✓
═══════════════════════════════════════════════════════
```

### Example objective.json

```json
{
  "objective": {
    "description": "Improve image classification accuracy to 90% or higher",
    "context": "Current model achieves 78% accuracy. Users report misclassifications on edge cases.",
    "constraints": [
      "Must not increase inference time beyond 200ms per image",
      "Model size must stay under 500MB"
    ]
  },
  "verification": {
    "command": "python scripts/benchmark_accuracy.py --dataset validation",
    "successCriteria": "accuracy >= 0.90",
    "metricsToTrack": ["accuracy", "precision", "recall", "f1_score", "inference_time_ms"]
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

### Key Differences from PRD Mode

| Aspect | PRD Mode | Objective Mode |
|--------|----------|----------------|
| **Input** | `prd.json` with user stories | `objective.json` with goal and metrics |
| **Progress** | Story-by-story (US-001, US-002...) | Metric-by-metric (accuracy: 0.78 → 0.85 → 0.90) |
| **Commits** | `feat: US-001 - Story Title` | `exp: Iteration N - Hypothesis description` |
| **Termination** | All stories pass | Success criteria met, plateau, or budget exhausted |
| **Memory** | What was implemented | What was tried and what worked |

### Use Cases

**Performance optimization:**
```bash
# Reduce API latency to under 100ms
./angainor.sh --objective 12
```

**Model accuracy improvement:**
```bash
# Achieve 90% accuracy on test dataset
./angainor.sh --objective 15
```

**Test coverage goals:**
```bash
# Reach 80% line coverage
./angainor.sh --objective 10
```

**Code quality metrics:**
```bash
# Reduce cyclomatic complexity below 10
./angainor.sh --objective 8
```

---

## Advanced Features

### 1. Skill Extraction (Claudeception)

Inspired by [Claudeception](https://github.com/blader/Claudeception), Angainor can automatically extract reusable knowledge from successful iterations and save it as Claude Code skills for future projects.

**How it works:**

1. Iteration completes successfully
2. Claude evaluates if the solution meets **quality gates**
3. If yes, outputs a `<<<SKILL_CANDIDATE>>>` block
4. `angainor.sh` parses and writes to `~/.claude/skills/angainor-learnings/`
5. Skill becomes available in all future Claude sessions

**Quality gates (ALL must pass):**
- **Non-obvious**: Not documented in standard libraries/frameworks
- **Reusable**: Applies beyond this specific project
- **Verified**: Tested and confirmed working in this iteration
- **Specific trigger**: Clear condition for when to apply it

**Categories:**

| Category | Purpose | Examples |
|----------|---------|----------|
| `error-resolutions` | Fixes for cryptic errors, version conflicts | "pnpm ENOENT error with turbo", "Vite HMR not working with React 19" |
| `patterns` | Reusable code patterns, architectural approaches | "Optimistic UI updates with Server Actions", "Type-safe environment variables" |
| `workflows` | Multi-step processes, debugging strategies | "Debugging Next.js hydration mismatches", "Setting up Playwright in CI" |

**Storage:** `~/.claude/skills/angainor-learnings/<category>/<name>.md`

### 2. Angainor Profile (Plugin Management)

Angainor configures a minimal plugin environment for autonomous execution by disabling plugins that interfere with the iteration loop.

**Disabled plugins:**

| Plugin | Reason |
|--------|--------|
| `automatic-code-review@claude-skillz` | Interferes with autonomous iteration flow |
| `explanatory-output-style@claude-plugins-official` | Adds unnecessary verbosity |

**Lifecycle:**
- `configure_angainor_profile()` disables plugins at startup
- `restore_plugins()` re-enables on exit (normal, Ctrl+C, or error)
- Missing plugins handled gracefully (no errors)

### 3. Metrics Tracking

Every iteration records performance metrics to `metrics.json`:

```json
{
  "iterations": [
    {
      "timestamp": "2026-01-20-14-30-00",
      "duration_seconds": 127,
      "story_id": "US-001",
      "status": "success",
      "lines_changed": 42,
      "files_changed": 3,
      "estimated_tokens": 5200,
      "failure_reason": ""
    }
  ]
}
```

**Metrics summary (printed on completion):**

```
═══════════════════════════════════════════════════════
  ANGAINOR METRICS SUMMARY
═══════════════════════════════════════════════════════
  Total iterations:     8
  Successful stories:   6
  Blocked stories:      1
  Failed iterations:    1
  Total duration:       15m 32s
  Average time/story:   1m 56s
═══════════════════════════════════════════════════════
```

### 4. Verification Enforcement

Angainor enforces evidence-based verification before accepting story completion:

**Verification formats accepted:**
- XML blocks: `<verification>...</verification>`
- Checkmarks: `✅ Criterion - evidence`

**Requirements:**
- Every acceptance criterion must have verification
- Must include concrete evidence (command output, file references)
- Any `NOT_SATISFIED` conclusion or `❌` fails the iteration

**Example verification (checkmark format):**

```markdown
## Verification

✅ Typecheck passes - ran npm run typecheck, exit 0
✅ UI displays correctly - tested in dev-browser, badge shows
✅ Filter persists - navigated to ?priority=high, refreshed, still active
```

### 5. Retry Logic & Error Handling

Angainor handles transient API errors gracefully:

- **Retry on**: Connection errors, rate limits, empty responses
- **Max retries**: 3 attempts with exponential backoff
- **Failure handling**: Records error in metrics, continues to next iteration
- **Error reporting**: Last response printed on unexpected exits

### 6. Transcript Indexing

All iteration transcripts are indexed for fast searching via `/read-transcript` skill:

```json
{
  "transcripts": [
    {
      "file": "2026-01-20-14-30-00-iteration-1.txt",
      "timestamp": "2026-01-20-14-30-00",
      "iteration": 1,
      "branch": "angainor/task-priority",
      "storyId": "US-001"
    }
  ]
}
```

### 7. Archiving

When switching to a new feature (different `branchName` in prd.json), Angainor automatically archives the previous run:

```
archive/
├── 2026-01-15-task-priority/
│   ├── prd.json
│   ├── progress.txt
│   └── transcripts/
└── 2026-01-18-user-auth/
    ├── prd.json
    ├── progress.txt
    └── transcripts/
```

---

## Key Concepts

### Story Sizing

**Each story must complete in ONE context window.**

✅ Right-sized:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with validation
- Write tests for a specific component

❌ Too large (split these):
- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API"

**Rule of thumb:** If you can't describe the change in 2-3 sentences, split it.

### Dependency Ordering

Stories execute by priority (1, 2, 3...). Order matters:

1. **Database schema** (migrations)
2. **Backend logic** (server actions, API)
3. **UI components** (that use the backend)
4. **Aggregate views** (dashboards, reports)

### Quality Gates

Angainor only commits code that passes quality checks. Configure in `prompt.md`:

```bash
npx tsc --noEmit  # TypeScript
npm test          # Tests
npm run lint      # Linting
```

For UI stories, add to acceptance criteria:
```
"Verify in browser using dev-browser skill"
```

### Fresh Context Per Iteration

Each iteration spawns a **new Claude instance with zero memory**. The only persistence:

- Git commits (code)
- `progress.txt` (learnings)
- `prd.json` (task status)
- `transcripts/` (searchable history)

---

## Memory Model

```
┌─────────────────────────────────────────────────────────┐
│ SHALLOW MEMORY (read every iteration)                   │
│  • prd.json      → What to do next                      │
│  • progress.txt  → Patterns and gotchas                 │
│  • git log       → Recent changes                       │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ DEEP MEMORY (search when needed)                        │
│  • transcripts/  → Full context from each iteration     │
│  • index.json    → Search by story, date, branch        │
└─────────────────────────────────────────────────────────┘
```

### progress.txt Format

Always **append**, never replace:

```markdown
## 2026-01-17 14:30 - US-003
Story: US-003 - Add priority selector
- Implemented dropdown with Radix UI
- Files: components/TaskEdit.tsx, actions.ts
- **Learnings:**
  - Use `<Select>` from @/components/ui/select
  - Server actions must revalidatePath after mutations
---
```

Consolidate reusable patterns at the **top** in a `## Codebase Patterns` section.

### prd.json Format

```json
{
  "project": "MyApp",
  "branchName": "angainor/feature-name",
  "description": "Feature description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add priority field to database",
      "description": "As a developer, I need to store priority...",
      "acceptanceCriteria": [
        "Add priority column: 'high' | 'medium' | 'low'",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

---

## Skills

Angainor includes four built-in skills for the PRD and Objective workflows:

### `/prd` - PRD Generator

**Description:** Generate detailed Product Requirements Documents from feature descriptions.

**Triggers:** `create a prd`, `write prd for`, `plan this feature`, `requirements for`, `spec out`

**Process:**
1. Ask 3-5 essential clarifying questions (with lettered options)
2. Generate structured PRD based on answers
3. Save to `tasks/prd-[feature-name].md`

**Output sections:**
- Introduction/Overview
- Goals
- User Stories (with acceptance criteria)
- Functional Requirements
- Non-Goals
- Design Considerations
- Technical Considerations
- Success Metrics
- Open Questions

**Key features:**
- Stories sized for one context window
- Verifiable acceptance criteria
- UI stories include "Verify in browser" criterion

### `/angainor` - PRD to JSON Converter

**Description:** Convert markdown PRDs to prd.json format for Angainor execution.

**Triggers:** `convert this prd`, `turn this into angainor format`, `create prd.json from this`, `angainor json`

**Process:**
1. Read existing PRD markdown
2. Split large stories if needed
3. Order by dependencies (schema → backend → UI)
4. Add required criteria (typecheck, browser verification)
5. Generate prd.json

**Story sizing rules:**
- Completable in ONE iteration (one context window)
- Describable in 2-3 sentences
- Max 5 files modified

**Dependency ordering:**
1. Database schema / migrations
2. Backend logic / server actions
3. UI components
4. Aggregate views / dashboards

### `/objective` - Objective Definition

**Description:** Interactive skill that helps define a measurable objective through guided questions.

**Triggers:** `define an objective`, `create objective.json`, `set up objective mode`, `/objective`

**Process:**
1. Ask clarifying questions about goal type, target, and constraints
2. Propose verification method and metrics to track
3. Suggest stopping conditions with sensible defaults
4. Present complete plan for approval
5. Generate `objective.json` after user approval

**Output sections:**
- Objective (description, context, constraints)
- Verification (command, success criteria, metrics)
- Stopping conditions (max iterations, plateau threshold, failure limit)

**Key features:**
- Type-specific defaults (performance, accuracy, coverage, quality)
- Offers to create benchmark scripts if none exist
- User can adjust any part of the proposal before approval
- Explains each stopping parameter in plain language

### `/read-transcript` - Transcript Search

**Description:** Search and retrieve context from previous iteration transcripts.

**Triggers:** `search transcripts`, `previous iteration`, `what happened in`, `read transcript`

**Search methods:**
- By story ID: `Search transcripts for story US-003`
- By date range: `Search transcripts from 2026-01-15 to 2026-01-17`
- By branch: `Search transcripts for branch angainor/auth-system`
- By iteration number: `Read transcript from iteration 5`

**Use cases:**
- Understanding HOW something was implemented
- Debugging issues from previous iterations
- Finding detailed context beyond progress.txt

---

## PRD Format

Angainor uses a JSON format for tracking story status and execution:

```json
{
  "project": "MyApp",
  "branchName": "angainor/feature-name-kebab-case",
  "description": "Brief feature description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Short descriptive title",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": [
        "Verifiable criterion 1",
        "Verifiable criterion 2",
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

### Field Reference

| Field | Type | Values | Description |
|-------|------|--------|-------------|
| `id` | string | `US-###` | Unique story identifier |
| `title` | string | - | Short descriptive title |
| `description` | string | - | User story in "As a...I want...so that" format |
| `acceptanceCriteria` | array | - | List of verifiable criteria |
| `priority` | number | 1, 2, 3... | Execution order (dependencies first) |
| `passes` | boolean | true/false | Whether story is complete |
| `status` | string | `pending`, `blocked`, `passed` | Rich state information |
| `attempts` | number | 0+ | How many iterations attempted this story |
| `notes` | string | - | Additional context or blockers |
| `blockedReason` | string (optional) | - | Why story is blocked (only on blocked stories) |

### Story Status Flow

```
pending → (attempted) → passed
   ↓
blocked (after multiple failures)
```

### Acceptance Criteria Guidelines

**Good (verifiable):**
- "Add `priority` column to tasks table with values 'high', 'medium', 'low'"
- "Filter dropdown shows options: All, High, Medium, Low"
- "Clicking delete shows confirmation dialog"
- "Typecheck passes"

**Bad (vague):**
- "Works correctly"
- "Good UX"
- "Handles edge cases"

**Required criteria:**
- Every story: `"Typecheck passes"`
- UI stories: `"Verify in browser using dev-browser skill"`

### Migration Tool

Migrate existing prd.json files to the new format with status/attempts fields:

```bash
./.angainor/scripts/migrate-prd.sh prd.json
```

---

## Configuration

### Claude Code Settings

The installer automatically configures `.claude/settings.json`:

```json
{
  "skills": [".angainor/skills"]
}
```

### Git Ignore

The installer adds these entries to `.gitignore`:

```gitignore
# Angainor generated files
prd.json
objective.json
progress.txt
.last-branch
transcripts/
screenshots/
metrics.json
```

### Directory Structure

After installation:

```
your-project/
├── .angainor/                    # Angainor internals (commit this)
│   ├── angainor.sh              # Main loop script
│   ├── prompt.md                # PRD mode agent instructions
│   ├── objective-prompt.md      # Objective mode agent instructions
│   ├── prd.json.example         # PRD format reference
│   ├── objective.json.example   # Objective format reference
│   ├── skills/                  # Claude Code skills
│   │   ├── prd/
│   │   ├── angainor/
│   │   ├── objective/           # Objective definition skill
│   │   └── read-transcript/
│   └── scripts/
│       └── migrate-prd.sh
├── angainor.sh                   # Wrapper script (commit this)
├── prd.json                      # Current PRD (generated, ignored)
├── objective.json                # Current objective (generated, ignored)
├── progress.txt                  # Learning log (generated, ignored)
├── transcripts/                  # Iteration logs (generated, ignored)
├── screenshots/                  # Browser verification (generated, ignored)
├── metrics.json                  # Performance data (generated, ignored)
└── archive/                      # Previous runs (generated, optional commit)
```

---

## Debugging

### Check Status

```bash
# Story progress
cat prd.json | jq '.userStories[] | {id, title, passes}'

# Recent learnings
tail -50 progress.txt

# Transcript index
cat transcripts/index.json | jq '.transcripts[]'

# Count complete/pending
cat prd.json | jq '[.userStories[] | select(.passes == true)] | length'
```

---

## Troubleshooting

### Claude API Errors

**Problem:** Transient API errors (ECONNRESET, rate limits, 503)

**Solution:** Angainor automatically retries with exponential backoff (max 3 attempts). If persistent, check:
- Claude Code authentication: `claude auth status`
- Network connectivity
- API rate limits (wait and retry)

### Verification Failures

**Problem:** `⚠ VERIFICATION ENFORCEMENT FAILED - Missing verification`

**Solution:** Angainor requires verification evidence. Check:
- Are `<verification>` XML blocks present in the output?
- OR are `✅` checkmarks present?
- Did the iteration complete before outputting verification?

The iteration will retry automatically.

### Story Never Completes

**Problem:** Story attempted multiple times but never passes

**Common causes:**
1. **Too large** - Split into smaller stories
2. **Missing dependencies** - Earlier story needs to complete first
3. **Flaky tests** - Fix test infrastructure
4. **Unclear criteria** - Acceptance criteria too vague

**Solution:**
1. Check `progress.txt` for attempt history
2. Read transcripts with `/read-transcript` for detailed context
3. Update prd.json to mark story as `blocked` if unsolvable
4. Split story or clarify acceptance criteria

### Branch Mismatch

**Problem:** Angainor creates commits on wrong branch

**Solution:** Ensure `branchName` in prd.json is correct. Angainor checks out/creates this branch automatically. If wrong:
1. Update `branchName` in prd.json
2. Manually checkout correct branch
3. Re-run Angainor

### Missing Skills

**Problem:** `/prd`, `/angainor`, or `/read-transcript` not found

**Solution:** Check Claude Code skills configuration:

```bash
cat .claude/settings.json
# Should include: {"skills": [".angainor/skills"]}
```

If missing, re-run installer or manually add to settings.

### Metrics Not Recording

**Problem:** `metrics.json` empty or not updating

**Solution:** Check:
1. File permissions on `metrics.json`
2. `jq` installed and in PATH
3. Iteration completed successfully (not interrupted)

Initialize manually if needed:

```bash
echo '{"iterations": []}' > metrics.json
```

### Manual Intervention

```bash
# Mark story complete manually
jq '.userStories[2].passes = true' prd.json > tmp.json && mv tmp.json prd.json

# Add learning
cat >> progress.txt << 'EOF'
## 2026-01-17 - US-003 (Manual Fix)
- Fixed manually due to [reason]
- Learning: [what to avoid]
---
EOF

# Resume
./angainor.sh 10
```

---

## Flowchart Visualization

Interactive React Flow diagram showing the Angainor execution flow.

### Setup

```bash
cd flowchart
npm install
npm run dev       # Development server
npm run build     # Production build
npm run lint      # ESLint check
```

### Technology Stack

- **React 19** - Latest React with modern features
- **TypeScript** - Type safety
- **Vite** - Fast build tooling
- **React Flow** - Interactive flowchart rendering

### Features

- Interactive node exploration
- Zoom and pan controls
- Color-coded nodes by category (input, process, decision, output)
- Responsive design

---

## Examples

### Example 1: Simple Feature (Task Priority)

**Run Angainor:**

```bash
./angainor.sh 5
```

**Iteration 1 output:**

```
═══════════════════════════════════════════════════════
  Angainor Iteration 1 of 5
═══════════════════════════════════════════════════════
  Calling Claude API (attempt 1/3)...

[Claude implements US-001, creates migration, runs typecheck]

## Verification

✅ Add priority column - migration created, column added with enum type
✅ Generate and run migration - `npm run db:migrate` succeeded
✅ Typecheck passes - ran npm run typecheck, exit 0

Iteration 1 complete. Continuing...
```

**Result:**
- Story US-001 marked `passes: true`
- Git commit: `feat: US-001 - Add priority field to database`
- Learning logged to `progress.txt`
- Transcript saved to `transcripts/2026-01-20-14-30-00-iteration-1.txt`

### Example 2: Blocked Story Handling

**Story US-005 encounters an issue:**

```json
{
  "id": "US-005",
  "title": "Real-time notifications",
  "status": "blocked",
  "attempts": 3,
  "blockedReason": "WebSocket integration requires infrastructure not in scope",
  "notes": "Needs separate infrastructure story"
}
```

**Angainor behavior:**
1. Attempts story 3 times
2. Marks as `blocked` after repeated failures
3. Documents blocker in `blockedReason`
4. Moves to next story (doesn't waste context)
5. Human can review and either fix blocker or split story

---

## File Reference

| File | Purpose | Modified By |
|------|---------|-------------|
| `.angainor/angainor.sh` | Main loop spawning Claude instances | Human (rarely) |
| `.angainor/prompt.md` | PRD mode iteration instructions | Human (customize) |
| `.angainor/objective-prompt.md` | Objective mode iteration instructions | Human (customize) |
| `angainor.sh` | Wrapper script | Generated by installer |
| `prd.json` | User stories with status (PRD mode) | Angainor |
| `objective.json` | Goal and metrics (Objective mode) | Angainor |
| `progress.txt` | Append-only learnings | Angainor |
| `transcripts/` | Full iteration logs | Angainor |
| `transcripts/index.json` | Searchable transcript index | Angainor |
| `metrics.json` | Performance metrics | Angainor |
| `archive/` | Previous Angainor runs | Angainor |
| `.claude/settings.json` | Skills configuration | Installer |

---

## Contributing

Contributions welcome! Areas of interest:

- Additional skills for common workflows
- Improved error recovery strategies
- Better visualization tools
- Integration with other AI coding tools

---

## License

MIT License - See LICENSE file for details.

---

## Acknowledgments

Based on the [Ralph pattern](https://ghuntley.com/ralph/) by [Geoffrey Huntley](https://ghuntley.com).

Skill extraction inspired by [Claudeception](https://github.com/blader/Claudeception) by [blader](https://github.com/blader).

Special thanks to the Claude Code team at Anthropic for building an excellent autonomous agent platform.

---

## Links

- **GitHub**: https://github.com/thepriceisright/angainor
- **Ralph Pattern**: https://ghuntley.com/ralph/
- **Claudeception**: https://github.com/blader/Claudeception
- **Claude Code**: https://claude.ai/code
- **Interactive Flowchart**: https://thepriceisright.github.io/angainor/

---

**Built with Claude Code • Powered by Anthropic's Claude**
