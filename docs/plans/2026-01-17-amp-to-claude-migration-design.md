# Ralph: Amp to Claude Migration Design

## Overview

Refactor Ralph to use Claude Code CLI instead of Amp, while preserving the "deep memory" capability through transcript logging and a searchable index.

## Changes

### 1. ralph.sh Modifications

**Core invocation (line 63):**
```bash
# Before (Amp)
OUTPUT=$(cat "$SCRIPT_DIR/prompt.md" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true

# After (Claude)
OUTPUT=$(claude --dangerously-skip-permissions --print < "$SCRIPT_DIR/prompt.md" 2>&1 | tee /dev/stderr "$TRANSCRIPT_FILE") || true
```

**New transcript logging:**
- Create `transcripts/` directory
- Save each iteration's full output to `transcripts/YYYY-MM-DD-HH-MM-SS-iteration-N.txt`
- Append metadata (iteration, timestamp, branch) to each transcript
- Maintain `transcripts/index.json` for searchable index
- Archive transcripts when branch changes (alongside prd.json/progress.txt)

**Index structure (`transcripts/index.json`):**
```json
{
  "transcripts": [
    {
      "file": "2026-01-17-14-30-00-iteration-1.txt",
      "timestamp": "2026-01-17T14:30:00",
      "iteration": 1,
      "branch": "ralph/feature-name",
      "storyId": "US-001"
    }
  ]
}
```

### 2. prompt.md Updates

- Remove Amp thread URL reference (`$AMP_CURRENT_THREAD_ID`)
- Replace with reference to `transcripts/` directory
- Remove `read_thread` tool mention
- Add instruction to use `read-transcript` skill for deep context

### 3. New Skill: read-transcript

**Location:** `skills/read-transcript/SKILL.md`

**Capabilities:**
- Read `transcripts/index.json` to find relevant transcripts
- Search by: story ID, date range, branch name, keyword
- Read full transcript files for detailed context
- Present relevant excerpts for current task

### 4. Documentation Updates

**README.md:**
- Replace "Amp" with "Claude Code" throughout
- Update prerequisites (Claude Code CLI instead of Amp CLI)
- Update skills installation path (~/.claude/skills/)
- Add section on transcript search feature

**AGENTS.md:**
- Replace "Amp" with "Claude Code"
- Update key files table to include transcripts/

## File Changes Summary

| File | Action |
|------|--------|
| `ralph.sh` | Modify - Claude invocation, transcript logging |
| `prompt.md` | Modify - Remove Amp references |
| `skills/read-transcript/SKILL.md` | Create - New skill |
| `README.md` | Modify - Update documentation |
| `AGENTS.md` | Modify - Update documentation |
| `transcripts/` | Create - New directory |
| `transcripts/index.json` | Create - Search index |

## Migration Notes

- Existing Amp users will need to install Claude Code CLI
- Previous progress.txt and prd.json files remain compatible
- No changes to prd.json format required
