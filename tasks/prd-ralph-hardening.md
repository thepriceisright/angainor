# PRD: Ralph Loop Hardening

## Introduction

Harden the Ralph autonomous agent loop based on learnings from a 10-iteration test run on the Weave project. The test achieved 100% success rate but revealed opportunities for improved reliability, better error handling, and comprehensive observability. These improvements will make Ralph more robust for production autonomous agent deployment.

### Background

Ralph is an autonomous AI agent loop that executes PRDs by spawning fresh Claude Code instances repeatedly until all tasks complete. Memory persists through git history, `prd.json` (task status), `progress.txt` (learnings), and `transcripts/`.

### Problem Statement

Current limitations identified:
1. **No verification enforcement** - Claude self-reports completion without proving acceptance criteria are met
2. **Binary error handling** - No graduated recovery strategy when stories fail
3. **No state validation** - Iterations can start with inconsistent git/JSON state
4. **Line-based sizing** - Poor proxy for actual context consumption
5. **No hallucination guardrails** - Autonomous loops can accumulate confident-but-wrong implementations
6. **Limited observability** - No metrics for debugging or optimization
7. **Ambiguous code review guidance** - Multiple iterations spent on stylistic fixes

## Goals

- Reduce failed iterations through pre-flight validation and state verification
- Preserve progress through graduated error recovery (vs. binary skip)
- Prevent context overflow with token-aware story sizing guidance
- Catch hallucinated implementations through grounding rules
- Enable debugging and optimization through comprehensive JSON metrics
- Enforce verification of acceptance criteria before marking stories complete
- Clarify code review scope to prevent iteration waste

## User Stories

### US-001: Add State Verification to prompt.md
**Description:** As a Ralph operator, I want each iteration to verify system state before proceeding so that iterations don't fail due to inconsistent state.

**Acceptance Criteria:**
- [ ] Add "Start-of-Iteration Verification" section to prompt.md
- [ ] Section includes: git status check, prd.json validity check, progress.txt continuity check
- [ ] Instructions are concise (under 20 lines added)
- [ ] Existing prompt.md structure preserved
- [ ] Typecheck passes (if applicable)

---

### US-002: Add Pre-Flight Validation to prompt.md
**Description:** As a Ralph operator, I want Claude to validate story feasibility before implementing so that context isn't wasted on doomed attempts.

**Acceptance Criteria:**
- [ ] Add "Pre-Implementation Checklist" section to prompt.md
- [ ] Checklist includes: scope clarity, dependency map (max 5 files), test strategy, failure modes
- [ ] Instructions fit in under 15 lines
- [ ] Existing prompt.md structure preserved
- [ ] Typecheck passes (if applicable)

---

### US-003: Add Verification Block Requirement to prompt.md
**Description:** As a Ralph operator, I want Claude to prove each acceptance criterion is satisfied before marking a story complete so that false completions are prevented.

**Acceptance Criteria:**
- [ ] Add "Before Marking Story Complete" section to prompt.md
- [ ] Section requires structured `<verification>` block with: criterion stated, evidence provided, SATISFIED/NOT_SATISFIED conclusion
- [ ] Instructions are concise (under 20 lines)
- [ ] Existing prompt.md structure preserved
- [ ] Typecheck passes (if applicable)

---

### US-004: Add Verification Enforcement to ralph.sh
**Description:** As a Ralph operator, I want ralph.sh to validate that verification was performed before accepting story completion so that the verification requirement is enforced, not just advisory.

**Acceptance Criteria:**
- [ ] ralph.sh checks for `<verification>` block in Claude output
- [ ] ralph.sh checks that no criterion has `NOT_SATISFIED` conclusion
- [ ] If verification missing or failed, iteration is marked as failed (does not count toward completion)
- [ ] Failure reason logged to transcript
- [ ] Existing ralph.sh functionality preserved
- [ ] Script passes shellcheck

---

### US-005: Add Graduated Error Recovery to prompt.md
**Description:** As a Ralph operator, I want Claude to follow a graduated recovery strategy when implementations fail so that valuable failure information is preserved.

**Acceptance Criteria:**
- [ ] Add "When Implementation Fails" section to prompt.md
- [ ] Section defines 3 attempt levels with escalating strategies
- [ ] Attempt 1: Re-read criteria, try alternative approach
- [ ] Attempt 2: Search transcripts, simplify to MVP
- [ ] Attempt 3: Document as BLOCKED with hypotheses, proceed to next story
- [ ] Instructions fit in under 30 lines
- [ ] Existing prompt.md structure preserved

---

### US-006: Add BLOCKED Status Support to prd.json
**Description:** As a Ralph operator, I want stories to have a BLOCKED status distinct from untried so that I can distinguish "tried and failed" from "not yet attempted."

**Acceptance Criteria:**
- [ ] Update prd.json.example to document `status` field: "pending" | "blocked" | "passed"
- [ ] Update prd.json.example to document `attempts` field (number)
- [ ] Update prd.json.example to document `blockedReason` field (string, optional)
- [ ] All new fields have sensible defaults for backward compatibility
- [ ] Typecheck passes (if applicable)

---

### US-007: Create prd.json Migration Script
**Description:** As a Ralph operator, I want a migration script to update existing prd.json files to the new format so that I don't have to manually edit them.

**Acceptance Criteria:**
- [ ] Create `scripts/migrate-prd.sh` script
- [ ] Script adds `status: "pending"` to stories where `passes: false`
- [ ] Script adds `status: "passed"` to stories where `passes: true`
- [ ] Script adds `attempts: 0` to all stories without it
- [ ] Script preserves all existing fields
- [ ] Script creates backup before modifying (`prd.json.bak`)
- [ ] Script is idempotent (safe to run multiple times)
- [ ] Script passes shellcheck

---

### US-008: Add Token-Based Sizing Guidance to prompt.md
**Description:** As a Ralph operator, I want Claude to assess story size by cognitive complexity, not line count, so that context overflow is prevented.

**Acceptance Criteria:**
- [ ] Add "Story Sizing Assessment" section to prompt.md
- [ ] Section defines "too large" criteria: >5 files to read, >3 system boundaries, >4000 token output estimate
- [ ] Instructions for handling oversized stories: document in progress.txt, skip to next
- [ ] Instructions fit in under 15 lines
- [ ] Existing prompt.md structure preserved

---

### US-009: Add Grounding Rules to prompt.md
**Description:** As a Ralph operator, I want Claude to follow grounding rules that prevent hallucinated implementations so that autonomous iterations don't accumulate errors.

**Acceptance Criteria:**
- [ ] Add "Implementation Grounding Rules" section to prompt.md
- [ ] Rule 1: No invented APIs - only use verifiable libraries/functions
- [ ] Rule 2: No assumed patterns - find existing pattern first, reference explicitly
- [ ] Rule 3: Uncertainty protocol - document uncertainty, implement simplest version
- [ ] Instructions fit in under 15 lines
- [ ] Existing prompt.md structure preserved

---

### US-010: Add Pre-Commit Self-Critique to prompt.md
**Description:** As a Ralph operator, I want Claude to perform self-critique before committing so that common issues are caught before they're committed.

**Acceptance Criteria:**
- [ ] Add "Before Running Git Commit" section to prompt.md
- [ ] Section includes: does it work? is it complete? is it safe?
- [ ] Instructions fit in under 10 lines
- [ ] Existing prompt.md structure preserved

---

### US-011: Add Comprehensive Metrics to ralph.sh
**Description:** As a Ralph operator, I want ralph.sh to output comprehensive metrics to JSON so that I can analyze performance and debug issues.

**Acceptance Criteria:**
- [ ] Create `metrics.json` file in script directory
- [ ] Each iteration records: timestamp, duration_seconds, story_id, status (success/failed/blocked), lines_changed, files_changed
- [ ] Add estimated_tokens field (based on transcript word count × 1.3)
- [ ] Add failure_reason field (empty on success)
- [ ] JSON is valid and parseable by jq
- [ ] Script passes shellcheck

---

### US-012: Add Metrics Summary on Completion
**Description:** As a Ralph operator, I want ralph.sh to output a summary of metrics when the loop completes so that I can quickly assess the run.

**Acceptance Criteria:**
- [ ] On loop completion (success or max iterations), print summary to stdout
- [ ] Summary includes: total iterations, successful stories, blocked stories, total duration, average time per story
- [ ] Summary is human-readable (not JSON)
- [ ] Script passes shellcheck

---

### US-013: Add Code Review Strategy to prompt.md
**Description:** As a Ralph operator, I want clear code review guidance so that iterations aren't wasted on stylistic fixes.

**Acceptance Criteria:**
- [ ] Add "Code Review Strategy" section to prompt.md
- [ ] Section distinguishes FIX (security, runtime errors, type safety) from SKIP (style, pre-existing code)
- [ ] Limit: max 1 iteration on code review fixes per story
- [ ] Instructions fit in under 15 lines
- [ ] Existing prompt.md structure preserved

---

### US-014: Update CLAUDE.md with New Patterns
**Description:** As a developer working on Ralph, I want CLAUDE.md updated to reflect the new patterns so that the documentation stays current.

**Acceptance Criteria:**
- [ ] Document new prd.json fields (status, attempts, blockedReason)
- [ ] Document metrics.json output location and format
- [ ] Document migration script usage
- [ ] Document verification enforcement behavior
- [ ] Keep additions concise (under 30 lines added)

## Functional Requirements

- **FR-1:** prompt.md must remain under 250 lines total after all additions
- **FR-2:** All new prd.json fields must have defaults for backward compatibility
- **FR-3:** ralph.sh must output valid JSON to metrics.json after each iteration
- **FR-4:** ralph.sh must validate `<verification>` block presence before accepting completion
- **FR-5:** Migration script must be idempotent and create backups
- **FR-6:** All bash scripts must pass shellcheck
- **FR-7:** Metrics JSON must be parseable by standard tools (jq, Python json module)

## Non-Goals

- No web dashboard for metrics visualization (use external tools)
- No automatic story splitting (document and skip only)
- No parallel story execution (future enhancement)
- No changes to the flowchart/ visualization tool
- No changes to existing skills (prd, ralph, read-transcript)
- No token counting integration with Claude API (use word-count estimation)

## Technical Considerations

- **Backward Compatibility:** All prd.json changes use optional fields with defaults
- **Shellcheck Compliance:** All bash modifications must pass `shellcheck -e SC2086`
- **JSON Validity:** Use `jq` for all JSON manipulation in ralph.sh
- **Minimal Prompt Growth:** Each prompt.md section should be 10-30 lines max
- **Verification Parsing:** Use grep/sed to detect `<verification>` blocks and `NOT_SATISFIED` strings

### Dependency Order

```
US-001 (state verification)     ─┐
US-002 (pre-flight validation)  ─┼─► US-014 (CLAUDE.md update)
US-003 (verification block)     ─┤
US-004 (enforcement) ◄───────────┘
US-005 (error recovery) ◄──── US-006 (BLOCKED status) ◄──── US-007 (migration script)
US-008 (sizing guidance)        ─┐
US-009 (grounding rules)        ─┼─► Independent of others
US-010 (self-critique)          ─┘
US-011 (metrics) ◄──── US-012 (summary)
US-013 (code review)            ─► Independent
```

## Success Metrics

- **Reliability:** Failed iteration rate < 5% (vs. current ~0% in test, but untested edge cases)
- **Observability:** All iterations produce complete metrics.json entries
- **Enforcement:** 100% of completed stories have `<verification>` blocks in transcripts
- **Backward Compatibility:** Existing prd.json files work without modification (migration optional)
- **Prompt Size:** prompt.md remains under 250 lines

## Open Questions

1. Should metrics.json be rotated/archived when switching branches (like transcripts)?
2. Should BLOCKED stories count toward max_iterations limit?
3. Should verification enforcement be opt-out via command-line flag for testing?
4. What's the right threshold for "too many files" in pre-flight check (currently 5)?
