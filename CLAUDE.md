# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Angainor?

Angainor is an autonomous AI agent loop that executes Product Requirements Documents (PRDs) by running Claude Code repeatedly until all tasks are complete. Each iteration spawns a fresh Claude instance with clean context. Memory persists through git history, structured files (`prd.json`, `progress.txt`), and full transcript logs in `transcripts/`.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

## Two Execution Modes

Angainor supports two distinct execution modes:

| Mode | Config File | Prompt File | Use When |
|------|-------------|-------------|----------|
| **PRD Mode** (default) | `prd.json` | `prompt.md` | Tasks are well-defined with clear acceptance criteria |
| **Objective Mode** | `objective.json` | `objective-prompt.md` | Goal is measurable but approach is unknown |

**PRD Mode**: Execute predefined user stories with known implementations. Each iteration completes one story then marks it done.

**Objective Mode**: Iterate toward a measurable goal through experimentation. Each iteration forms a hypothesis, tests it, and adjusts based on results.

### When to Use Each Mode

**Use PRD Mode when:**
- You can break the work into discrete user stories
- Each story has clear acceptance criteria
- The implementation approach is known upfront
- Examples: Add feature X, Fix bug Y, Refactor module Z

**Use Objective Mode when:**
- You have a measurable goal but unknown path
- The approach requires experimentation
- You need to iterate until a metric threshold is met
- Examples: Improve accuracy to 90%, Reduce latency to <100ms, Achieve 80% test coverage

## Commands

```bash
# Run Angainor in PRD mode (default - from a project that has prd.json)
./angainor.sh [max_iterations]        # default: 10 iterations
./angainor.sh --prd [max_iterations]  # explicit PRD mode

# Run Angainor in Objective mode (from a project that has objective.json)
./angainor.sh --objective [max_iterations]

# Debugging options
./angainor.sh --objective --verbose 100     # Verbose output for debugging
./angainor.sh --objective --debug 100       # Full debug logging to angainor-debug.log
./angainor.sh --objective --debug=/path/to/file.log 100  # Custom debug log path

# Help
./angainor.sh --help                  # Show all options

# Flowchart visualization (interactive React Flow diagram)
cd flowchart && npm install && npm run dev    # dev server
cd flowchart && npm run build                 # production build
cd flowchart && npm run lint                  # lint check
```

### Debugging Options

| Flag | Description |
|------|-------------|
| `--verbose`, `-v` | Show detailed info during API calls (response lengths, exit codes, stderr) |
| `--debug` | Write full debug log to `angainor-debug.log` (implies verbose) |
| `--debug=FILE` | Write debug log to custom path |
| `--timeout=SECS` | Set iteration timeout (default: 3600s/60min objective, 600s PRD) |
| `--no-timeout` | Disable iteration timeout entirely |

**When to use:**
- **Empty responses**: Use `--verbose` to see what Claude is returning
- **API errors**: Use `--verbose` to see the actual error patterns matched
- **Full diagnosis**: Use `--debug` to capture everything for later analysis
- **Very long benchmarks**: Use `--timeout=7200` or `--no-timeout` for iterations over 60min

## Repository Structure

```
├── angainor.sh              # Main bash loop that spawns fresh Claude instances
├── prompt.md             # Instructions for PRD mode iterations
├── objective-prompt.md   # Instructions for Objective mode iterations
├── prd.json.example      # Example PRD format for reference
├── objective.json.example # Example Objective format for reference
├── skills/               # Claude Code skills for the Angainor workflow
│   ├── prd/              # Generate PRDs from feature descriptions
│   ├── angainor/         # Convert markdown PRDs to prd.json format
│   ├── objective/        # Interactive objective definition with clarifying questions
│   └── read-transcript/  # Search previous iteration transcripts
└── flowchart/            # Interactive React Flow visualization (Vite + React 19 + TypeScript)
```

## Architecture: The Angainor Loop

```
1. Read prd.json → Find next story where passes=false
2. Read progress.txt → Learn from previous iterations (check Codebase Patterns section first)
3. Implement ONLY that single story
4. Run quality checks (typecheck, tests)
5. Commit if checks pass: feat: [Story ID] - [Story Title]
6. Update prd.json → Set passes=true
7. Append learnings to progress.txt
8. Save full transcript to transcripts/
9. Spawn fresh Claude instance → REPEAT
10. When all stories have passes=true → output <promise>COMPLETE</promise>
```

## Key Patterns

### Memory Model (How Context Persists Between Iterations)
- **Git commits**: Implementation memory (code changes)
- **progress.txt**: Learning memory (append-only patterns and gotchas)
- **prd.json**: Task status memory (which stories are done)
- **transcripts/**: Deep context memory (searchable via read-transcript skill)

### Story Sizing Rule
Each user story must be completable in ONE context window. If you cannot describe the change in 2-3 sentences, it's too big—split it.

### Dependency Ordering
Stories execute in priority order (1, 2, 3...). Correct order: Database schema → Backend logic → UI components → Aggregate views.

### Progress File Format
Always APPEND to progress.txt, never replace:
```
## [Date/Time] - [Story ID]
Story: [Story ID from prd.json]
- What was implemented
- Files changed
- **Learnings for future iterations:**
  - Patterns discovered
  - Gotchas encountered
---
```

Consolidate reusable patterns at the TOP of progress.txt in a `## Codebase Patterns` section.

### Completion Signal
When all stories have `passes: true`, output: `<promise>COMPLETE</promise>`

### Verification Enforcement (PRD Mode)
angainor.sh enforces that each iteration includes `<verification>` blocks before accepting story completion. If blocks are missing or contain `NOT_SATISFIED`, the iteration fails and doesn't count toward completion.

Flexible verification: angainor.sh accepts either `<verification>` XML blocks OR ✅ checkmarks as valid verification evidence.

### Iteration Boundaries (Objective Mode)
Each objective iteration MUST end with `<iteration>COMPLETE</iteration>` (or a termination signal). This ensures:
- ONE experiment per iteration (prevents runaway sessions)
- Clean handoff to next fresh Claude instance
- Proper metrics extraction before iteration ends

**Required signals:**
- `<metrics>{...}</metrics>` - Measurements from this experiment
- `<iteration>COMPLETE</iteration>` - Normal iteration end
- `<objective>SUCCESS|IMPOSSIBLE|PLATEAU</objective>` - Terminal states

### Live Output (Objective Mode Default)
Both modes now use `--print` for reliability (the old `script`+FIFO mechanism was removed due to compatibility issues with Claude Code CLI v2.1.31+). The `--live` flag now controls whether output is shown on the terminal via `tail -f` while capturing.

Objective mode still defaults to `--live` for visibility during long benchmarks. The generous timeout (60min default) handles long-running tasks.

**Flags:**
- `--live` - Show Claude output on terminal in real-time (default for objective mode)
- `--no-live` - Capture output silently (default for PRD mode)

### Plateau-Breaking Protocol (Objective Mode)
When iterations show diminishing returns, the Plateau-Breaking Protocol forces approach diversity:

**Escalation Levels:**
| Level | Trigger | Required Behavior |
|-------|---------|-------------------|
| EXPLORE | Normal state | Standard hypothesis formation |
| PIVOT | 2+ iterations without significant improvement | Must try different approach category |
| REFRAME | 4+ iterations stalled | Must challenge assumptions or problem framing |

**Approach Categories** (every hypothesis must belong to one):
- `PARAMETER_TUNING` - Adjust thresholds, hyperparameters, config values
- `ALGORITHM_CHANGE` - Swap one method for a different one
- `DATA_PIPELINE` - Change how input is processed, filtered, augmented
- `ARCHITECTURE` - Structural changes to system design
- `ERROR_ANALYSIS` - Deep-dive into failure cases to find root causes
- `ASSUMPTION_CHALLENGE` - Question whether the problem is framed correctly

**Key rules:**
- In PIVOT/REFRAME: must select approach category NOT used in last 2 iterations
- Each iteration logs its approach category to progress.txt for category rotation
- Before signaling PLATEAU: must have tried at least 3 different categories

See `objective-prompt.md` for the full protocol with XML output formats.

### Priority Directive System (Objective Mode)
Iterations can set mandatory priorities for the next iteration, ensuring important discoveries are acted upon:

**Setting a priority** (current iteration):
```xml
<set_priority>
  <directive>Try GPT-4V for schedule extraction</directive>
  <reason>Current model has API errors and poor accuracy</reason>
  <approachCategory>ALGORITHM_CHANGE</approachCategory>
  <suggestions>["gpt-4v", "gemini-pro-vision"]</suggestions>
</set_priority>
```

**Responding to a priority** (next iteration - MANDATORY):
```xml
<priority_response>
  <action>ATTEMPTING|SKIPPING</action>
  <directive>[The directive text]</directive>
  <skip_reason>CONSTRAINT_VIOLATION|ALREADY_TRIED|SUPERSEDED</skip_reason>  <!-- only if SKIPPING -->
  <response>[What you're doing or why you're skipping]</response>
</priority_response>
```

**Key rules:**
- Priority is stored in `status.nextIterationPriority` in objective.json
- Next iteration MUST respond with `<priority_response>` before any other analysis
- Valid skip reasons: `CONSTRAINT_VIOLATION`, `ALREADY_TRIED` (cite iteration), `SUPERSEDED`
- If ATTEMPTING: the directive becomes the iteration's hypothesis
- Priority is cleared after response (regardless of attempt or skip)

See `objective-prompt.md` for full details.

### LLM Output Extraction (Objective Mode)
When the agent doesn't output proper XML tags, angainor.sh uses an LLM (via OpenRouter) to extract structured data from natural language output.

**Extraction chain:**
1. **XML parsing** (free, instant) - Try to extract `<metrics>`, `<set_priority>` tags
2. **LLM extraction** (~$0.001, ~2s) - Use Claude Haiku 4.5 to parse natural language
3. **progress.txt parsing** (free) - Regex extraction from progress file

**What it extracts:**
- Metrics (numerical measurements like accuracy, precision, recall)
- Priority directives (suggestions for next iteration from "Consider:", "Try:", etc.)
- Iteration completion status

**Requirements:**
- `OPENROUTER_API_KEY` in `.env` file or environment
- Cost: ~$0.001 per extraction (~$0.10 for 100 iterations)

**Flags:**
- `--no-llm-extraction`: Disable LLM extraction (not recommended)

### Angainor Profile
angainor.sh configures a minimal environment for autonomous runs using three mechanisms:

**Per-session CLI flags** (primary — no global state changes):
- `--strict-mcp-config --mcp-config <empty>` - Disables all MCP servers
- `--disable-slash-commands` - Disables all skills/slash commands
- `--no-session-persistence` - Prevents session data from accumulating on disk

**Disabled plugins** (secondary — restored on exit):
- `automatic-code-review@claude-skillz` - Interferes with autonomous iteration flow
- `explanatory-output-style@claude-plugins-official` - Adds unnecessary verbosity

**Auto-memory isolation** (CLI 2.1.32+ — backed up and cleared during runs):
- Claude Code 2.1.32+ automatically records and recalls memories via files in `~/.claude/projects/<path>/memory/`
- Angainor manages its own cross-iteration memory via `progress.txt`, so auto-memory is redundant and could inject stale context from prior interactive sessions
- `configure_angainor_profile()` backs up the entire memory directory and removes it
- `restore_angainor_profile()` removes any files written during the run, then restores the original directory from backup
- No CLI flag exists to disable auto-memory; file-level isolation is required

**Profile lifecycle:**
- `configure_angainor_profile()` disables plugins and isolates auto-memory at startup
- `restore_angainor_profile()` re-enables plugins and restores auto-memory on exit (normal, Ctrl+C, or error)
- Missing plugins are handled gracefully (no errors)

**Minimum CLI version:** 2.1.20+ (earlier versions may lack required flags)

### Headless Browser Testing
The install script creates `.mcp.json` with Playwright configured for containerized environments:

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

**Key flags:**
- `--no-sandbox`: Required for Docker/containers without elevated privileges (Chrome sandbox uses Linux namespaces)
- `--headless`: Run without GUI for autonomous operation
- `--browser chromium`: Use Chromium (most reliable in containers)

**Browser binaries**: Playwright downloads browsers to `~/.cache/ms-playwright/`. Run `npx playwright install chromium` if missing.

### Metrics Output
angainor.sh writes iteration metrics to `metrics.json` in the script directory:
```json
{"iterations": [{"timestamp": "...", "duration_seconds": N, "story_id": "US-001", "status": "success|failed|blocked", "lines_changed": N, "files_changed": N, "estimated_tokens": N, "failure_reason": ""}]}
```
A human-readable summary prints on loop completion.

### Skill Extraction (Claudeception)
Angainor iterations can extract reusable skills for cross-project learning. When an iteration discovers non-obvious, verified knowledge, it outputs a `<<<SKILL_CANDIDATE>>>` block that angainor.sh parses and writes to disk.

**Quality gates** (all must pass): Non-obvious, reusable beyond this project, verified working, has specific trigger.

**Categories:** `error-resolutions`, `patterns`, `workflows` | **Storage:** `~/.claude/skills/angainor-learnings/<category>/<name>.md`

**Output format:**
```
<<<SKILL_CANDIDATE>>>
category: [error-resolutions|patterns|workflows]
name: [kebab-case-name]
description: Use when [trigger]
content: [Problem, Solution, Example, Verification sections]
<<<END_SKILL_CANDIDATE>>>
```
Skills are automatically available to future Claude Code sessions across all projects.

## Skills Usage

| Skill | Trigger phrases | Purpose |
|-------|-----------------|---------|
| `prd` | "create a prd", "write prd for", "plan this feature" | Generate detailed PRDs with clarifying questions |
| `angainor` | "convert this prd", "angainor json", "create prd.json" | Convert markdown PRDs to prd.json format |
| `objective` | "define an objective", "create objective.json", "set up objective mode" | Interactive objective definition with clarifying questions |
| `read-transcript` | "search transcripts", "previous iteration", "what happened in" | Search deep context from transcripts/ |

## prd.json Format

```json
{
  "project": "ProjectName",
  "branchName": "angainor/feature-name-kebab-case",
  "description": "Feature description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Story title",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": ["Criterion 1", "Typecheck passes"],
      "priority": 1,
      "passes": false,
      "status": "pending",
      "attempts": 0,
      "notes": ""
    }
  ]
}
```

**Story status fields:**
- `status`: `"pending"` | `"blocked"` | `"passed"` - richer state than boolean `passes`
- `attempts`: number - how many iterations attempted this story
- `blockedReason`: string (optional) - why a story is blocked, only on blocked stories

Use `scripts/migrate-prd.sh [path/to/prd.json]` to migrate existing PRDs to the new format.

## objective.json Format

```json
{
  "objective": {
    "description": "What we're trying to achieve (measurable goal)",
    "context": "Background info explaining current state and what's been tried",
    "constraints": ["Hard limits that must not be violated"]
  },
  "verification": {
    "command": "python scripts/benchmark.py",
    "successCriteria": "accuracy >= 0.90",
    "metricsToTrack": ["accuracy", "precision", "recall", "inference_time_ms"]
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
    "metricHistory": [],
    "nextIterationPriority": null
  }
}
```

**Objective section:**
- `description`: The measurable goal (what success looks like)
- `context`: Current state and background (helps agent understand the problem)
- `constraints`: Non-negotiable limits (agent must never violate these)

**Verification section:**
- `command`: Shell command to run benchmark/measurement
- `successCriteria`: Expression that evaluates to true when objective is achieved
- `metricsToTrack`: Metrics to extract from each iteration for tracking progress

**Stopping section:**
- `maxIterations`: Maximum iterations before automatic termination
- `plateauThreshold`: Automatic plateau detection configuration
  - `metric`: Which metric to monitor for improvement
  - `minImprovement`: Minimum change required to count as improvement
  - `windowSize`: Number of iterations to consider for plateau detection
- `maxConsecutiveFailures`: Stop after this many failed iterations in a row

**Status section (managed by angainor.sh):**
- `state`: `pending` | `running` | `success` | `plateau` | `impossible` | `max_iterations`
- `iterations`: Number of completed iterations
- `bestMetrics`: Best values achieved for each tracked metric
- `metricHistory`: Array of metrics from each iteration (for trend analysis)
- `nextIterationPriority`: Priority directive for next iteration (see Priority Directive System above)

## Objective Mode Termination Conditions

Objective mode has four termination conditions:

| Signal | Exit Code | Meaning |
|--------|-----------|---------|
| `SUCCESS` | 0 | Objective achieved - `successCriteria` expression is true |
| `IMPOSSIBLE` | 2 | Objective cannot be achieved (with evidence) |
| `PLATEAU` | 3 | Diminishing returns - no improvement across `windowSize` iterations |
| `MAX_ITERATIONS` | 4 | Iteration budget exhausted without success |

**SUCCESS**: Agent outputs `<objective>SUCCESS</objective>` when metrics satisfy `successCriteria`.

**IMPOSSIBLE**: Agent outputs `<objective>IMPOSSIBLE</objective>` with `<reason>` and `<category>` (technical|scope|resource) when there's concrete evidence the goal cannot be achieved.

**PLATEAU**: Either agent-signaled (with `<attempts>` and `<suggestion>`) or automatically detected when the tracked metric shows less than `minImprovement` over `windowSize` iterations.

**MAX_ITERATIONS**: Triggered when iteration count reaches the lower of CLI argument or `stopping.maxIterations`.

## Quality Requirements

- All commits must pass quality checks (typecheck, lint, test)
- UI stories require browser verification with dev-browser skill
- Every story's acceptance criteria must include "Typecheck passes"
- Update AGENTS.md files when discovering reusable patterns
