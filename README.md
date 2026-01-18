# Ralph

![Ralph](ralph.webp)

**Ralph is an autonomous AI agent loop that executes Product Requirements Documents (PRDs) by running Claude Code repeatedly until all tasks are complete.** Each iteration is a fresh Claude instance with clean context. Memory persists through git history, structured files, and full transcript logs.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

[Read the in-depth article on how to use Ralph](https://x.com/ryancarson/status/2008548371712135632)

---

## Table of Contents

- [What is Ralph?](#what-is-ralph)
- [The Problem Ralph Solves](#the-problem-ralph-solves)
- [How Ralph Works](#how-ralph-works)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Complete Workflow](#complete-workflow)
- [Key Files and Directories](#key-files-and-directories)
- [Memory Model](#memory-model)
- [Transcript Search](#transcript-search)
- [Critical Concepts](#critical-concepts)
- [Skills Reference](#skills-reference)
- [Debugging Guide](#debugging-guide)
- [Archiving](#archiving)
- [Customization](#customization)
- [Troubleshooting](#troubleshooting)
- [References](#references)

---

## What is Ralph?

Ralph is a bash script that spawns Claude Code instances in a loop, each working autonomously to implement one user story from a structured PRD. Unlike traditional AI coding assistants that require continuous human interaction, Ralph:

- **Works autonomously** - Give it a PRD and walk away
- **Uses fresh context per iteration** - No context pollution across tasks
- **Validates quality** - Runs typechecks, tests, and other quality gates
- **Maintains memory** - Persists learnings through git, progress logs, and transcripts
- **Scales with complexity** - Can execute multi-day features with dozens of stories

Ralph is ideal for:
- Implementing well-defined features end-to-end
- Database schema migrations with UI changes
- Systematic refactoring across multiple files
- Adding test coverage to existing code
- Any multi-step development task with clear acceptance criteria

---

## The Problem Ralph Solves

### Traditional AI Coding Challenges

1. **Context Window Limitations**: Large features exceed a single conversation context
2. **Context Pollution**: Earlier work in the conversation affects later work unpredictably
3. **Manual Coordination**: Humans must remember what's done and what's next
4. **Quality Regression**: AI may skip tests or break existing code without feedback loops
5. **Lost Context**: Switching between tasks loses important implementation details

### Ralph's Solution

Ralph treats each user story as an independent task with:
- **Fresh context** per iteration (no pollution)
- **Structured memory** through files (git, progress.txt, prd.json, transcripts)
- **Automated quality gates** (typecheck, tests, CI)
- **Deep historical context** through searchable transcript logs
- **Autonomous progression** through prioritized user stories

---

## How Ralph Works

[![Ralph Flowchart](ralph-flowchart.png)](https://snarktank.github.io/ralph/)

**[View Interactive Flowchart](https://snarktank.github.io/ralph/)** - Click through each step with animations

### The Loop

```
┌─────────────────────────────────────────────────────────┐
│  1. Read prd.json → Find next story where passes=false │
├─────────────────────────────────────────────────────────┤
│  2. Read progress.txt → Learn from previous iterations │
├─────────────────────────────────────────────────────────┤
│  3. Implement ONLY that single story                    │
├─────────────────────────────────────────────────────────┤
│  4. Run quality checks (typecheck, tests)               │
├─────────────────────────────────────────────────────────┤
│  5. Commit if checks pass                               │
├─────────────────────────────────────────────────────────┤
│  6. Update prd.json → Set passes=true                   │
├─────────────────────────────────────────────────────────┤
│  7. Append learnings to progress.txt                    │
├─────────────────────────────────────────────────────────┤
│  8. Save full transcript to transcripts/                │
├─────────────────────────────────────────────────────────┤
│  9. Update transcript index for searchability           │
├─────────────────────────────────────────────────────────┤
│ 10. Spawn fresh Claude instance → REPEAT               │
└─────────────────────────────────────────────────────────┘
```

When all stories have `passes: true`, Ralph outputs `<promise>COMPLETE</promise>` and exits.

---

## Prerequisites

### Required

- **[Claude Code CLI](https://claude.ai/code)** - Installed and authenticated
- **jq** - JSON processor (`brew install jq` on macOS, `apt install jq` on Linux)
- **Git repository** - For your project

### Recommended

- **TypeScript** - For typecheck quality gates (or equivalent for your language)
- **Test framework** - For automated verification
- **CI/CD pipeline** - To catch regressions between iterations

---

## Quick Start

### 1. Install Ralph

**Option A: Copy to your project**

```bash
# From your project root
mkdir -p scripts/ralph
cd scripts/ralph
curl -O https://raw.githubusercontent.com/snarktank/ralph/main/ralph.sh
curl -O https://raw.githubusercontent.com/snarktank/ralph/main/prompt.md
chmod +x ralph.sh
```

**Option B: Install skills globally**

```bash
# Copy skills to Claude Code config
cd ~/.claude/skills
git clone https://github.com/snarktank/ralph.git ralph-skills
cp -r ralph-skills/skills/* .
rm -rf ralph-skills

# Or copy individually:
cp -r /path/to/ralph/skills/prd ~/.claude/skills/
cp -r /path/to/ralph/skills/ralph ~/.claude/skills/
cp -r /path/to/ralph/skills/read-transcript ~/.claude/skills/
```

### 2. Create a PRD

Start a Claude Code session:

```
Load the prd skill and create a PRD for [your feature description]
```

Answer the clarifying questions. The skill saves output to `tasks/prd-[feature-name].md`.

### 3. Convert PRD to Ralph Format

```
Load the ralph skill and convert tasks/prd-[feature-name].md to prd.json
```

This creates `prd.json` with user stories structured for autonomous execution.

### 4. Run Ralph

```bash
./scripts/ralph/ralph.sh 10
```

Ralph will autonomously implement each story, validate quality, commit, and move to the next.

---

## Complete Workflow

### Phase 1: Planning (With Claude Code)

```bash
# Start Claude Code
claude

# In Claude Code session:
# > Load the prd skill and create a PRD for [feature description]
# Answer clarifying questions...
# PRD saved to tasks/prd-feature-name.md

# Convert to JSON format:
# > Load the ralph skill and convert tasks/prd-feature-name.md to prd.json
# prd.json created
```

### Phase 2: Autonomous Execution (Ralph Loop)

```bash
# Start Ralph
./scripts/ralph/ralph.sh 20

# Ralph runs autonomously:
# - Iteration 1: Implements US-001 (database schema)
# - Iteration 2: Implements US-002 (server action)
# - Iteration 3: Implements US-003 (UI component)
# - ...
# - Iteration N: All stories complete → <promise>COMPLETE</promise>
```

### Phase 3: Review and Iterate

```bash
# Check status
cat prd.json | jq '.userStories[] | {id, title, passes}'

# Review learnings
cat progress.txt

# Search transcripts for specific context
claude
# > Load read-transcript skill and search for iterations about US-003

# Review git history
git log --oneline -20

# If quality issues found, fix in progress.txt and re-run
```

### Phase 4: Integration

```bash
# Create pull request
git push origin ralph/feature-name
gh pr create --title "Feature: [name]" --body "Implemented by Ralph"

# Or merge directly
git checkout main
git merge ralph/feature-name
git push
```

---

## Key Files and Directories

### Core Files

| File | Purpose | Modified By |
|------|---------|-------------|
| `ralph.sh` | The bash loop that spawns fresh Claude instances | Human (rarely) |
| `prompt.md` | Instructions given to each Claude instance | Human (customize) |
| `prd.json` | User stories with `passes` status (the task list) | Ralph (auto) |
| `progress.txt` | Append-only learnings for future iterations | Ralph (auto) |

### Example Files

| File | Purpose |
|------|---------|
| `prd.json.example` | Example PRD format for reference |

### Directories

| Directory | Purpose | Contents |
|-----------|---------|----------|
| `transcripts/` | Full logs from each iteration | `*.txt` files |
| `transcripts/index.json` | Searchable index of all transcripts | JSON metadata |
| `skills/` | Claude Code skills for Ralph workflow | `prd/`, `ralph/`, `read-transcript/` |
| `archive/` | Previous Ralph runs (auto-archived) | `YYYY-MM-DD-feature-name/` |
| `flowchart/` | Interactive visualization of Ralph's workflow | React Flow app |

### Skills

| Skill | Purpose | When to Use |
|-------|---------|-------------|
| `skills/prd/` | Generate detailed PRDs with user stories | Starting a new feature |
| `skills/ralph/` | Convert markdown PRDs to prd.json | After PRD generation |
| `skills/read-transcript/` | Search previous iteration transcripts | Debugging, learning context |

---

## Memory Model

Ralph maintains memory across iterations through four mechanisms:

### 1. Git History (Implementation Memory)

**What**: Commits from each completed story
**When**: After quality checks pass
**Format**: `feat: US-001 - Add priority field to database`

**Purpose**:
- Shows code evolution
- Enables rollback if needed
- Provides diff context for debugging

### 2. progress.txt (Learning Memory)

**What**: Append-only log of discoveries and patterns
**When**: After each story completion
**Format**:
```
## 2026-01-17 14:30 - US-003
Story: US-003 - Add priority selector to task edit
- Implemented dropdown component with Radix UI
- Files changed: components/TaskEdit.tsx, actions.ts
- **Learnings for future iterations:**
  - Use `<Select>` from @/components/ui/select
  - Server actions must revalidatePath after mutations
  - Task IDs are UUIDs, not integers
---
```

**Purpose**:
- Pass context to next iteration
- Document gotchas and patterns
- Build institutional knowledge

### 3. prd.json (Task Status Memory)

**What**: Structured list of user stories with completion status
**When**: Updated after each successful story
**Format**:
```json
{
  "id": "US-001",
  "title": "Add priority field to database",
  "passes": true,  // ← Updated by Ralph
  "notes": ""      // ← Can add debugging notes
}
```

**Purpose**:
- Track which stories are complete
- Determine next story to work on
- Provide stopping condition

### 4. transcripts/ (Deep Context Memory)

**What**: Full conversation logs from each iteration
**When**: After every iteration (success or failure)
**Format**:
```
transcripts/
  2026-01-17-14-30-00-iteration-1.txt  (full conversation)
  2026-01-17-14-45-00-iteration-2.txt
  index.json  (searchable metadata)
```

**Purpose**:
- Search for specific implementation details
- Understand how something was built
- Debug issues by reviewing full context
- Learn from both successes and failures

### Memory Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│ SHALLOW MEMORY (read every iteration)                      │
│  • prd.json         → What to do next                       │
│  • progress.txt     → Key learnings and patterns            │
│  • git log          → Recent code changes                   │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ DEEP MEMORY (search when needed)                           │
│  • transcripts/     → Full context from previous iterations │
│  • index.json       → Find relevant transcripts by:         │
│                       - Story ID                            │
│                       - Date range                          │
│                       - Branch name                         │
│                       - Iteration number                    │
└─────────────────────────────────────────────────────────────┘
```

---

## Transcript Search

### Why Transcripts?

`progress.txt` captures high-level learnings, but sometimes you need to know:
- The exact error message that was encountered
- How a specific implementation decision was made
- What alternative approaches were tried
- The full conversation that led to a solution

Transcripts preserve the complete context from each iteration.

### Using the read-transcript Skill

Load the skill in a Claude Code session:

```
Load the read-transcript skill and [search query]
```

### Search Examples

**By Story ID:**
```
Search transcripts for story US-003
```

**By Date Range:**
```
Search transcripts from 2026-01-15 to 2026-01-17
```

**By Branch:**
```
Search transcripts for branch ralph/auth-system
```

**By Iteration Number:**
```
Read transcript from iteration 5
```

**By Topic/Keyword:**
The skill will search through the index and relevant transcript content:
```
Find iterations related to database migration errors
```

### Transcript Index Structure

`transcripts/index.json` contains metadata for fast searching:

```json
{
  "transcripts": [
    {
      "file": "2026-01-17-14-30-00-iteration-1.txt",
      "timestamp": "2026-01-17-14-30-00",
      "iteration": 1,
      "branch": "ralph/task-priority",
      "storyId": "US-001"
    }
  ]
}
```

### When to Search Transcripts

- **Debugging**: "Why did iteration 5 fail on that test?"
- **Understanding**: "How was the authentication middleware implemented?"
- **Learning**: "What error messages indicate database connection issues?"
- **Context**: "What files were modified when adding that feature?"

---

## Critical Concepts

### 1. Each Iteration = Fresh Context

**Every iteration spawns a new Claude Code instance with zero memory of previous conversations.**

**The ONLY memory between iterations is:**
- Git commits (code changes)
- `progress.txt` (learnings)
- `prd.json` (task status)
- `transcripts/` (deep context via search)

**Why fresh context?**
- Prevents context pollution (earlier work affecting later work)
- Forces explicit knowledge transfer (better documentation)
- Enables parallel execution (future enhancement)
- Maintains predictable behavior

**Implications:**
- Each story must be fully self-contained
- All context must be in git, progress.txt, or searchable via transcripts
- Do not reference "earlier in this conversation" across iterations

### 2. Small Tasks Are Critical

**Rule: Each user story must be completable in one Claude Code context window.**

If a story is too large, the LLM will run out of context before finishing and produce incomplete or broken code.

#### Right-Sized Stories ✓

- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new validation logic
- Add a filter dropdown to a list view
- Write tests for a specific component
- Add an index to a database table

#### Too Large ✗ (Split These)

- "Build the entire dashboard" → Split into schema, queries, components, filters
- "Add authentication" → Split into schema, middleware, login UI, session handling
- "Refactor the API" → Split into one story per endpoint or pattern
- "Add real-time updates" → Split into WebSocket setup, subscription logic, UI updates

**Rule of Thumb**: If you cannot describe the change in 2-3 sentences, it is too large.

### 3. AGENTS.md Updates Are Critical

Ralph should update `AGENTS.md` files when discovering patterns that will help future iterations (or future human developers).

**When to update AGENTS.md:**
- You discover a non-obvious pattern ("use X for Y")
- You encounter a gotcha ("do not forget Z when changing W")
- You identify useful context ("component X is located here")

**Example AGENTS.md additions:**
```markdown
## Database Patterns
- Always use `IF NOT EXISTS` in migrations
- Use `sql<number>` template for complex aggregations

## Component Patterns
- Task components are in `components/tasks/`
- All server actions must call `revalidatePath()` after mutations

## Testing Patterns
- UI tests require dev server on port 3000
- Mock database with `vi.mock('@/db')`
```

**Why AGENTS.md?**
Claude Code automatically reads `AGENTS.md` files in the codebase. By updating them, you create institutional knowledge that benefits both future Ralph iterations and human developers.

### 4. Feedback Loops Are Required

**Ralph only works if there are automated quality gates.**

Without feedback loops, broken code compounds across iterations.

#### Required Feedback Loops

1. **Typecheck**: Catches type errors before commit
   ```bash
   npx tsc --noEmit
   ```

2. **Tests**: Verify behavior and prevent regressions
   ```bash
   npm test
   ```

3. **Lint**: Enforce code style and catch common errors
   ```bash
   npm run lint
   ```

#### Optional Feedback Loops

4. **Build**: Ensure production build succeeds
   ```bash
   npm run build
   ```

5. **CI**: Run full test suite in cloud
   ```bash
   # GitHub Actions, CircleCI, etc.
   ```

6. **Browser Testing**: For UI stories, verify in actual browser
   ```
   Verify in browser using dev-browser skill
   ```

**Configure in prompt.md**:
Edit the quality check commands in `prompt.md` to match your project's requirements.

### 5. Browser Verification for UI Stories

Frontend changes are NOT complete until visually verified.

**Requirement**: UI stories must include this acceptance criterion:
```
"Verify in browser using dev-browser skill"
```

**Ralph will**:
1. Load the dev-browser skill
2. Navigate to the relevant page
3. Interact with the UI (click, type, etc.)
4. Verify the changes work as expected
5. Take screenshots if needed

**Why?**
- Typechecks do not catch visual bugs
- Tests do not catch layout issues
- Only browser verification confirms UI actually works

### 6. Stop Condition

Ralph checks after each story completion: Are ALL stories complete?

```javascript
// In prd.json
const allComplete = userStories.every(story => story.passes === true)
```

If true, Ralph outputs:
```xml
<promise>COMPLETE</promise>
```

The bash loop detects this and exits with code 0.

### 7. Dependency Order Matters

Stories execute in **priority order** (1, 2, 3...). Earlier stories must NOT depend on later stories.

**Correct order**:
1. Database schema (migrations)
2. Backend logic (server actions, API routes)
3. UI components (that use the backend)
4. Aggregate views (dashboards, reports)

**Wrong order**:
1. UI component (depends on schema)
2. Database schema ← This should be first!

The `ralph` skill enforces this when converting PRDs.

---

## Skills Reference

Ralph uses three custom Claude Code skills.

### skills/prd - PRD Generator

**Purpose**: Create detailed Product Requirements Documents

**Triggers**:
```
create a prd
write prd for [feature]
plan this feature
requirements for [feature]
```

**Output**: `tasks/prd-[feature-name].md`

**Process**:
1. Asks clarifying questions about the feature
2. Analyzes project structure and existing patterns
3. Generates user stories with acceptance criteria
4. Considers dependencies and edge cases
5. Saves markdown PRD to `tasks/` directory

**When to use**: Starting a new feature or major change

### skills/ralph - PRD to JSON Converter

**Purpose**: Convert markdown PRDs to Ralph's JSON format

**Triggers**:
```
convert this prd
turn this into ralph format
create prd.json from this
ralph json
```

**Output**: `prd.json`

**Process**:
1. Reads the markdown PRD
2. Splits large features into right-sized stories
3. Orders stories by dependency
4. Adds quality criteria (typecheck, tests, browser verification)
5. Generates `prd.json` with sequential IDs (US-001, US-002...)

**Key features**:
- **Archiving**: If `prd.json` exists with different `branchName`, archives it first
- **Story sizing**: Ensures each story is completable in one iteration
- **Dependency ordering**: Database → Backend → UI → Aggregates
- **Quality gates**: Adds "Typecheck passes" to all stories
- **Browser verification**: Adds browser check to UI stories

**When to use**: After creating a PRD, before running Ralph

### skills/read-transcript - Transcript Search

**Purpose**: Search and retrieve context from previous iterations

**Triggers**:
```
read transcript
previous iteration
what happened in [story/iteration]
search transcripts
```

**Process**:
1. Reads `transcripts/index.json`
2. Searches by story ID, date, branch, or iteration number
3. Reads relevant transcript files
4. Extracts and presents key information

**Search methods**:
- By story ID: `search transcripts for story US-003`
- By date: `search transcripts from 2026-01-15`
- By branch: `search transcripts for branch ralph/auth-system`
- By iteration: `read transcript from iteration 5`

**When to use**:
- Debugging: Understanding why something failed
- Learning: How was X implemented?
- Context: What files were modified?
- Errors: What error messages were encountered?

---

## Debugging Guide

### Check Current Status

```bash
# See which stories are done
cat prd.json | jq '.userStories[] | {id, title, passes}'

# View recent learnings
cat progress.txt | tail -50

# Check git history
git log --oneline -10

# See transcript index
cat transcripts/index.json | jq '.transcripts[]'

# Count completed vs pending stories
cat prd.json | jq '[.userStories[] | select(.passes == true)] | length'
cat prd.json | jq '[.userStories[] | select(.passes == false)] | length'
```

### Common Issues

#### Issue: Ralph Keeps Failing on Same Story

**Symptoms**: Same story fails multiple iterations

**Debug**:
```bash
# Find transcripts for that story
cat transcripts/index.json | jq '.transcripts[] | select(.storyId == "US-003")'

# Read the latest failure transcript
cat transcripts/2026-01-17-15-30-00-iteration-5.txt
```

**Solutions**:
1. Story may be too large → Split it in `prd.json`
2. Acceptance criteria may be unclear → Clarify in `prd.json`
3. Test/build command may be wrong → Update `prompt.md`
4. Dependency missing → Add earlier story or update `progress.txt`

#### Issue: Quality Checks Failing

**Symptoms**: Typecheck or tests fail, preventing commit

**Debug**:
```bash
# Run quality checks manually
npx tsc --noEmit
npm test

# Check what files changed
git status
git diff
```

**Solutions**:
1. Fix the error manually and add note to `progress.txt`
2. Update acceptance criteria to be more specific
3. Add pattern to `progress.txt` so future iterations avoid it

#### Issue: Story Marked Complete But Broken

**Symptoms**: `passes: true` but code does not work

**Debug**:
```bash
# Find when it was marked complete
git log --all --grep="US-003"

# Read that iteration's transcript
# (use timestamp from git commit)
cat transcripts/[timestamp]-iteration-N.txt
```

**Solutions**:
1. Acceptance criteria were too vague → Improve them
2. Quality checks were insufficient → Add more checks to `prompt.md`
3. Browser verification was skipped → Enforce it in acceptance criteria

#### Issue: Ralph Reached Max Iterations

**Symptoms**: `Ralph reached max iterations (N) without completing all tasks.`

**Debug**:
```bash
# Check progress
cat prd.json | jq '.userStories[] | select(.passes == false)'

# Review recent iterations
cat progress.txt | tail -100
```

**Solutions**:
1. Increase max iterations: `./ralph.sh 30`
2. Stories are too large → Split them
3. Quality checks too strict → Adjust in `prompt.md`
4. Resume: Ralph will continue from last incomplete story

### Manual Intervention

If Ralph gets stuck, you can intervene:

```bash
# 1. Fix the issue manually
# (edit files, run tests, commit)

# 2. Update prd.json
# Set the current story to passes: true
jq '.userStories[2].passes = true' prd.json > tmp.json && mv tmp.json prd.json

# 3. Update progress.txt
cat >> progress.txt << EOF
## $(date +%Y-%m-%d-%H-%M) - US-003 (Manual Fix)
Story: US-003 - Add priority selector
- Fixed manually due to [reason]
- Issue was: [description]
- **Learning**: [what to avoid in future]
---
EOF

# 4. Resume Ralph
./ralph.sh 10
```

### Resetting Ralph

To start over (useful for testing):

```bash
# Archive current run
DATE=$(date +%Y-%m-%d)
BRANCH=$(jq -r '.branchName' prd.json | sed 's|^ralph/||')
mkdir -p archive/$DATE-$BRANCH
cp prd.json progress.txt archive/$DATE-$BRANCH/
cp -r transcripts archive/$DATE-$BRANCH/

# Reset
echo "# Ralph Progress Log" > progress.txt
echo "Started: $(date)" >> progress.txt
echo "---" >> progress.txt
jq '.userStories[].passes = false' prd.json > tmp.json && mv tmp.json prd.json
rm -rf transcripts/*.txt
echo '{"transcripts": []}' > transcripts/index.json

# Start fresh
./ralph.sh 20
```

---

## Archiving

Ralph automatically archives previous runs when starting a new feature.

### When Archiving Happens

**Trigger**: You run `ralph.sh` and `prd.json` has a different `branchName` than the last run

**Example**:
1. You completed `ralph/task-priority` feature
2. You create new `prd.json` with `branchName: "ralph/auth-system"`
3. You run `./ralph.sh`
4. Ralph detects branch change and archives the old run

### What Gets Archived

- `prd.json` (the completed task list)
- `progress.txt` (all learnings)
- `transcripts/` (all iteration logs)

### Archive Location

```
archive/
  2026-01-17-task-priority/
    prd.json
    progress.txt
    transcripts/
      index.json
      2026-01-17-14-30-00-iteration-1.txt
      2026-01-17-14-45-00-iteration-2.txt
      ...
```

**Naming**: `YYYY-MM-DD-[feature-name]`
- Date: When archived
- Feature name: From `branchName` with `ralph/` prefix removed

### After Archiving

Ralph resets for the new feature:
1. Creates fresh `progress.txt` with header
2. Creates fresh `transcripts/index.json`
3. Deletes old transcript `.txt` files
4. Keeps new `prd.json` intact

### Manual Archiving

You can manually archive before running Ralph:

```bash
# Archive current run
DATE=$(date +%Y-%m-%d)
BRANCH=$(jq -r '.branchName' prd.json | sed 's|^ralph/||')
ARCHIVE_DIR="archive/$DATE-$BRANCH"

mkdir -p "$ARCHIVE_DIR"
cp prd.json progress.txt "$ARCHIVE_DIR/"
cp -r transcripts "$ARCHIVE_DIR/"

# Reset for new feature
echo "# Ralph Progress Log" > progress.txt
echo "Started: $(date)" >> progress.txt
echo "---" >> progress.txt
echo '{"transcripts": []}' > transcripts/index.json
rm transcripts/*.txt
```

### Restoring from Archive

To resume or review an archived run:

```bash
# Copy archived files back
cp archive/2026-01-17-task-priority/prd.json .
cp archive/2026-01-17-task-priority/progress.txt .
cp -r archive/2026-01-17-task-priority/transcripts .

# Resume Ralph (will continue from last incomplete story)
./ralph.sh 10
```

---

## Customization

### Customizing prompt.md

Edit `prompt.md` to customize Ralph's behavior for your project:

```markdown
## Quality Requirements

- ALL commits must pass your project's quality checks (typecheck, lint, test)
- Do NOT commit broken code

# ← Customize these commands for your project:
6. Run quality checks (e.g., typecheck, lint, test)
```

**Common customizations**:

```bash
# Python project
python -m pytest
python -m mypy .

# Go project
go test ./...
go build ./...

# Ruby project
bundle exec rspec
bundle exec rubocop

# Rust project
cargo test
cargo clippy
```

### Customizing Story Format

The `prd.json` format is flexible. Add custom fields:

```json
{
  "id": "US-001",
  "title": "Add priority field",
  "description": "As a user...",
  "acceptanceCriteria": [...],
  "priority": 1,
  "passes": false,
  "notes": "",

  // Custom fields:
  "estimatedTime": "30 minutes",
  "complexity": "low",
  "labels": ["database", "migration"],
  "assignee": "ralph"
}
```

Ralph ignores custom fields but they can help with project management.

### Customizing Quality Gates

Add additional checks in `prompt.md`:

```markdown
## Quality Requirements

- Typecheck passes: `npx tsc --noEmit`
- Tests pass: `npm test`
- Lint passes: `npm run lint`
- Build succeeds: `npm run build`
- Bundle size under 500KB: `npm run analyze`
- Accessibility checks pass: `npm run a11y`
- No console.log statements: `grep -r "console.log" src/`
```

### Customizing Archive Location

Edit `ralph.sh`:

```bash
# Change archive directory
ARCHIVE_DIR="$SCRIPT_DIR/.ralph-archive"  # Hidden folder
# or
ARCHIVE_DIR="$HOME/ralph-archives/$(basename $PWD)"  # Per-project in home
```

### Adding Custom Skills

Create your own skills for project-specific tasks:

```bash
mkdir -p ~/.claude/skills/my-skill
cat > ~/.claude/skills/my-skill/SKILL.md << 'EOF'
---
name: my-skill
description: "Custom skill for [purpose]"
---

# My Skill

[Skill documentation]
EOF
```

Use in PRD acceptance criteria:
```json
{
  "acceptanceCriteria": [
    "Feature works correctly",
    "Run my-skill to verify [thing]",
    "Typecheck passes"
  ]
}
```

---

## Troubleshooting

### Ralph Hangs or Times Out

**Symptom**: Iteration takes extremely long or never completes

**Possible causes**:
1. Story is too large (LLM spinning on complex logic)
2. Quality check command hangs (waiting for input, infinite loop)
3. Claude Code session has an issue

**Solutions**:
```bash
# Kill Ralph
Ctrl+C

# Check what it was working on
tail -100 transcripts/[latest].txt

# Split the story or fix the command, then resume
./ralph.sh 10
```

### Git Conflicts

**Symptom**: Ralph cannot commit due to merge conflicts

**Cause**: Main branch updated while Ralph was running

**Solution**:
```bash
# Pause Ralph (Ctrl+C)

# Update from main
git fetch origin
git rebase origin/main

# Resolve conflicts manually
# Then resume Ralph
./ralph.sh 10
```

### Transcript Index Corrupted

**Symptom**: `jq` errors when reading `transcripts/index.json`

**Solution**:
```bash
# Rebuild index from transcript files
cd transcripts
echo '{"transcripts": []}' > index.json

for file in *.txt; do
  TIMESTAMP=$(echo "$file" | grep -oP '\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}')
  ITERATION=$(echo "$file" | grep -oP 'iteration-\K\d+')
  BRANCH=$(grep "^Branch:" "$file" | cut -d' ' -f2 || echo "unknown")
  STORY=$(grep -oP 'feat: \K[A-Z]+-\d+' "$file" | head -1 || echo "unknown")

  jq --arg file "$file" \
     --arg ts "$TIMESTAMP" \
     --arg iter "$ITERATION" \
     --arg branch "$BRANCH" \
     --arg story "$STORY" \
     '.transcripts += [{"file": $file, "timestamp": $ts, "iteration": ($iter|tonumber), "branch": $branch, "storyId": $story}]' \
     index.json > index.json.tmp && mv index.json.tmp index.json
done
```

### Stories Complete But Ralph Continues

**Symptom**: All stories have `passes: true` but Ralph keeps running

**Cause**: Ralph did not output `<promise>COMPLETE</promise>`

**Solution**:
```bash
# Verify all complete
cat prd.json | jq '.userStories[] | select(.passes == false)'

# If none, manually stop Ralph (Ctrl+C)

# Check latest transcript for why COMPLETE was not output
tail -100 transcripts/[latest].txt
```

### Permission Denied on ralph.sh

**Symptom**: `bash: ./ralph.sh: Permission denied`

**Solution**:
```bash
chmod +x ralph.sh
./ralph.sh 10
```

### jq Command Not Found

**Symptom**: `bash: jq: command not found`

**Solution**:
```bash
# macOS
brew install jq

# Linux (Debian/Ubuntu)
sudo apt install jq

# Linux (RHEL/CentOS)
sudo yum install jq

# Verify
jq --version
```

---

## References

### Documentation

- [Geoffrey Huntley's Ralph Article](https://ghuntley.com/ralph/) - Original pattern and philosophy
- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code) - Claude Code CLI reference
- [Interactive Flowchart](https://snarktank.github.io/ralph/) - Visual guide to how Ralph works

### Related Projects

- [Claude Code Skills](https://github.com/anthropics/claude-code-skills) - Official skill examples
- [Amp Documentation](https://amp.dev/) - Original autonomous agent platform (Ralph migrated from)

### Community

- [Discussion Thread](https://x.com/ryancarson/status/2008548371712135632) - How to use Ralph in production

### Example PRDs

See `prd.json.example` for a complete example of:
- Right-sized user stories
- Dependency ordering
- Acceptance criteria format
- Quality gate inclusion

### Contributing

Ralph is open source. Contributions welcome:
- Report issues
- Share your PRD patterns
- Contribute new skills
- Improve documentation

---

## License

MIT License - See LICENSE file for details

---

## Acknowledgments

- **Geoffrey Huntley** - Original Ralph pattern and philosophy
- **Anthropic** - Claude Code platform
- **Contributors** - Everyone who has improved Ralph

---

**Remember**: Ralph is a tool for automating the tedious parts of software development. It works best when:
- Stories are right-sized (completable in one iteration)
- Quality gates are automated (typecheck, tests, CI)
- Learnings are captured (progress.txt, AGENTS.md)
- Context is searchable (transcripts)

Start small, iterate, and let Ralph handle the grunt work while you focus on architecture and design.
