# Ralph

![Ralph](ralph.webp)

**Ralph is an autonomous AI agent loop that executes Product Requirements Documents (PRDs) by running Claude Code repeatedly until all tasks are complete.** Each iteration spawns a fresh Claude instance with clean context. Memory persists through git history, structured files, and searchable transcript logs.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

[![Interactive Flowchart](ralph-flowchart.png)](https://snarktank.github.io/ralph/)

**[View Interactive Flowchart](https://snarktank.github.io/ralph/)** — Click through each step with animations

---

## Why Ralph?

Traditional AI coding faces these challenges:

| Problem | Ralph's Solution |
|---------|------------------|
| Context window limits | Fresh context per story, unlimited total capacity |
| Context pollution | Each iteration starts clean |
| Manual coordination | Autonomous progression through PRD |
| Quality regression | Automated quality gates before every commit |
| Lost implementation details | Searchable transcript logs |

Ralph is ideal for: feature implementation, schema migrations, systematic refactoring, adding test coverage, and any multi-step task with clear acceptance criteria.

---

## Quick Start

### 1. Install

```bash
# Copy to your project
mkdir -p scripts/ralph && cd scripts/ralph
curl -O https://raw.githubusercontent.com/snarktank/ralph/main/ralph.sh
curl -O https://raw.githubusercontent.com/snarktank/ralph/main/prompt.md
chmod +x ralph.sh

# Install skills globally (optional but recommended)
cd ~/.claude/skills
git clone https://github.com/snarktank/ralph.git ralph-repo
cp -r ralph-repo/skills/* . && rm -rf ralph-repo
```

### 2. Create PRD

```
# In Claude Code session:
> Load the prd skill and create a PRD for [your feature]
```

Answer the clarifying questions. Output: `tasks/prd-[feature].md`

### 3. Convert to JSON

```
> Load the ralph skill and convert tasks/prd-[feature].md to prd.json
```

### 4. Run

```bash
./scripts/ralph/ralph.sh 20  # max 20 iterations
```

Ralph implements each story, validates, commits, and continues until all stories pass.

---

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│  1. Read prd.json → Find next story where passes=false  │
│  2. Read progress.txt → Learn from previous iterations  │
│  3. Implement that single story                         │
│  4. Run quality checks (typecheck, tests, lint)         │
│  5. Commit if checks pass                               │
│  6. Update prd.json → passes=true                       │
│  7. Append learnings to progress.txt                    │
│  8. Save transcript to transcripts/                     │
│  9. Spawn fresh Claude → REPEAT                         │
└─────────────────────────────────────────────────────────┘
         ↓ When all stories pass ↓
      Output: <promise>COMPLETE</promise>
```

---

## Prerequisites

**Required:**
- [Claude Code CLI](https://claude.ai/code) — installed and authenticated
- [jq](https://jqlang.github.io/jq/) — `brew install jq` or `apt install jq`
- Git repository

**Recommended:**
- TypeScript/type checker for your language
- Test framework
- CI/CD pipeline

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

Ralph only commits code that passes quality checks. Configure in `prompt.md`:

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
  "branchName": "ralph/feature-name",
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

| Skill | Triggers | Purpose |
|-------|----------|---------|
| **prd** | `create a prd`, `write prd for`, `plan this feature` | Generate PRDs with clarifying questions |
| **ralph** | `convert this prd`, `ralph json`, `create prd.json` | Convert markdown PRD to JSON format |
| **read-transcript** | `search transcripts`, `previous iteration` | Search deep context from past iterations |

### Transcript Search Examples

```
Search transcripts for story US-003
Search transcripts from 2026-01-15 to 2026-01-17
Search transcripts for branch ralph/auth-system
Read transcript from iteration 5
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

### Common Issues

**Story keeps failing:**
1. Story too large → Split it
2. Unclear acceptance criteria → Clarify in prd.json
3. Missing dependency → Add earlier story or update progress.txt

**Quality checks failing:**
```bash
npx tsc --noEmit  # Run manually
npm test
git diff          # Check changes
```

**Ralph reached max iterations:**
```bash
./ralph.sh 30     # Increase limit and resume
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
./ralph.sh 10
```

---

## Archiving

Ralph auto-archives when `branchName` changes between runs:

```
archive/
  2026-01-17-task-priority/
    prd.json
    progress.txt
    transcripts/
```

**Manual archive:**
```bash
DATE=$(date +%Y-%m-%d)
BRANCH=$(jq -r '.branchName' prd.json | sed 's|^ralph/||')
mkdir -p archive/$DATE-$BRANCH
cp prd.json progress.txt archive/$DATE-$BRANCH/
cp -r transcripts archive/$DATE-$BRANCH/
```

**Restore:**
```bash
cp archive/2026-01-17-feature/prd.json .
cp archive/2026-01-17-feature/progress.txt .
cp -r archive/2026-01-17-feature/transcripts .
./ralph.sh 10
```

---

## Customization

### Quality Gates (prompt.md)

```markdown
## Quality Requirements
- Typecheck: `npx tsc --noEmit`
- Tests: `npm test`
- Lint: `npm run lint`
- Build: `npm run build`
```

**Language-specific:**
```bash
# Python
python -m pytest && python -m mypy .

# Go
go test ./... && go build ./...

# Rust
cargo test && cargo clippy
```

### Custom Skills

```bash
mkdir -p ~/.claude/skills/my-skill
cat > ~/.claude/skills/my-skill/SKILL.md << 'EOF'
---
name: my-skill
description: "Custom skill for [purpose]"
---
# My Skill
[Instructions]
EOF
```

---

## File Reference

| File | Purpose | Modified By |
|------|---------|-------------|
| `ralph.sh` | Main loop spawning Claude instances | Human (rarely) |
| `prompt.md` | Instructions for each iteration | Human (customize) |
| `prd.json` | User stories with status | Ralph |
| `progress.txt` | Append-only learnings | Ralph |
| `transcripts/` | Full iteration logs | Ralph |
| `transcripts/index.json` | Searchable transcript index | Ralph |
| `archive/` | Previous Ralph runs | Ralph |

---

## Flowchart Development

The interactive flowchart is a React Flow application:

```bash
cd flowchart
npm install
npm run dev      # Development server
npm run build    # Production build
npm run lint     # Lint check
```

Deploys automatically to GitHub Pages on push to main.

---

## References

- [Geoffrey Huntley's Ralph](https://ghuntley.com/ralph/) — Original pattern
- [Claude Code Docs](https://docs.anthropic.com/en/docs/claude-code) — CLI reference
- [Interactive Flowchart](https://snarktank.github.io/ralph/) — Visual guide
- [prd.json.example](prd.json.example) — Example PRD format

---

## License

MIT License

---

## Acknowledgments

- **Geoffrey Huntley** — Original Ralph pattern
- **Anthropic** — Claude Code platform
