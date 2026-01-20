# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Angainor?

Angainor is an autonomous AI agent loop that executes Product Requirements Documents (PRDs) by running Claude Code repeatedly until all tasks are complete. Each iteration spawns a fresh Claude instance with clean context. Memory persists through git history, structured files (`prd.json`, `progress.txt`), and full transcript logs in `transcripts/`.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

## Commands

```bash
# Run Angainor (from a project that has prd.json)
./angainor.sh [max_iterations]    # default: 10 iterations

# Flowchart visualization (interactive React Flow diagram)
cd flowchart && npm install && npm run dev    # dev server
cd flowchart && npm run build                 # production build
cd flowchart && npm run lint                  # lint check
```

## Repository Structure

```
├── angainor.sh              # Main bash loop that spawns fresh Claude instances
├── prompt.md             # Instructions given to each Claude instance during Angainor execution
├── prd.json.example      # Example PRD format for reference
├── skills/               # Claude Code skills for the Angainor workflow
│   ├── prd/              # Generate PRDs from feature descriptions
│   ├── angainor/            # Convert markdown PRDs to prd.json format
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

### Verification Enforcement
angainor.sh enforces that each iteration includes `<verification>` blocks before accepting story completion. If blocks are missing or contain `NOT_SATISFIED`, the iteration fails and doesn't count toward completion.

Flexible verification: angainor.sh accepts either `<verification>` XML blocks OR ✅ checkmarks as valid verification evidence.

### Angainor Profile
angainor.sh configures a minimal plugin environment for autonomous runs:

**Disabled plugins** (restored on exit):
- `automatic-code-review@claude-skillz` - Interferes with autonomous iteration flow
- `explanatory-output-style@claude-plugins-official` - Adds unnecessary verbosity

**Plugin lifecycle:**
- `configure_angainor_profile()` disables plugins at startup
- `restore_plugins()` re-enables on exit (normal, Ctrl+C, or error)
- Missing plugins are handled gracefully (no errors)

**Minimum plugin set** (what remains enabled):
- Core: Essential Claude Code functionality
- Testing: Framework detection, test runners
- Domain: Project-specific skills (prd, angainor, read-transcript)

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

## Quality Requirements

- All commits must pass quality checks (typecheck, lint, test)
- UI stories require browser verification with dev-browser skill
- Every story's acceptance criteria must include "Typecheck passes"
- Update AGENTS.md files when discovering reusable patterns
