# PRD: Auto-Learning (Claudeception Integration)

## Introduction

Integrate automatic skill extraction into the Ralph loop, enabling cross-project learning. After each successful iteration, Claude evaluates whether non-obvious, reusable knowledge was discovered. If quality gates pass, it outputs a structured block that ralph.sh writes to `~/.claude/skills/ralph-learnings/`. This creates a growing skill library that benefits all future Ralph runs across all projects.

Based on [Claudeception](https://github.com/blader/Claudeception) by blader.

## Goals

- Automatically capture non-obvious discoveries from Ralph iterations
- Persist learned skills at user level for cross-project benefit
- Apply strict quality gates to prevent noise (non-obvious, reusable, verified, specific trigger)
- Organize skills by category for easy browsing
- Zero overhead when no extractable knowledge exists

## User Stories

### US-001: Add skill extraction instructions to prompt.md
**Description:** As a Ralph iteration, I need instructions on when and how to evaluate for skill extraction so I can output candidates when quality gates pass.

**Acceptance Criteria:**
- [ ] Add "Skill Extraction (Claudeception)" section to prompt.md
- [ ] Document all 4 quality gates (non-obvious, reusable, verified, specific trigger)
- [ ] Document when to extract vs when NOT to extract
- [ ] Document the 3 categories (error-resolutions, patterns, workflows)
- [ ] Document the `<<<SKILL_CANDIDATE>>>` output format with all required fields
- [ ] Section is ~60 lines or less

### US-002: Add write_skill_candidate function to ralph.sh
**Description:** As ralph.sh, I need to detect and parse skill candidate blocks from iteration output so skills can be written to disk.

**Acceptance Criteria:**
- [ ] Add SKILL_DIR constant pointing to `~/.claude/skills/ralph-learnings`
- [ ] Add `write_skill_candidate()` function that extracts category, name, description, content
- [ ] Function validates all required fields are present
- [ ] Function validates category is in allowed list (error-resolutions, patterns, workflows)
- [ ] Function skips gracefully if block malformed or missing
- [ ] Function skips if skill with same name already exists (no overwrites)

### US-003: Write skill files with correct format
**Description:** As ralph.sh, I need to write extracted skills with proper SKILL.md format so Claude Code can discover and load them.

**Acceptance Criteria:**
- [ ] Create category subdirectory if it doesn't exist
- [ ] Write skill file with YAML frontmatter (only `name` and `description` fields)
- [ ] Description preserved exactly as provided (should start with "Use when...")
- [ ] Content body preserved with all sections
- [ ] Append Origin section with extracted timestamp, project name, and story ID
- [ ] Output success message: "✓ Extracted skill: [category]/[name].md"

### US-004: Integrate extraction into main loop
**Description:** As ralph.sh, I need to call skill extraction after successful iterations so discoveries are captured automatically.

**Acceptance Criteria:**
- [ ] Call `write_skill_candidate` after `record_metrics "success"` line
- [ ] Pass OUTPUT and STORY_ID to function
- [ ] Extraction runs on every successful iteration (no flag needed)
- [ ] Extraction failures don't break the main loop

### US-005: Test bash extraction with valid input
**Description:** As a developer, I need to verify the extraction function works correctly with well-formed input.

**Acceptance Criteria:**
- [ ] Create test script `scripts/test-skill-extraction.sh`
- [ ] Test extracts all fields correctly from valid skill candidate block
- [ ] Test creates correct directory structure
- [ ] Test writes valid YAML frontmatter
- [ ] Test preserves multiline content correctly
- [ ] All assertions pass

### US-006: Test bash extraction edge cases
**Description:** As a developer, I need to verify the extraction function handles edge cases gracefully.

**Acceptance Criteria:**
- [ ] Test: missing skill candidate block → function returns 0, no output
- [ ] Test: malformed block (missing fields) → warning message, no file created
- [ ] Test: invalid category → warning message, no file created
- [ ] Test: duplicate skill name → warning message, existing file not overwritten
- [ ] All assertions pass

### US-007: Document auto-learning in CLAUDE.md
**Description:** As a developer reading CLAUDE.md, I need to understand the auto-learning feature so I know how it works.

**Acceptance Criteria:**
- [ ] Add "Skill Extraction (Claudeception)" subsection under Key Patterns
- [ ] Document quality gates (brief summary)
- [ ] Document output format reference
- [ ] Document storage location and categories
- [ ] Note cross-project learning benefit
- [ ] Section is ~20 lines or less

### US-008: End-to-end integration test
**Description:** As a developer, I need to verify the complete flow works from iteration output to skill file on disk.

**Acceptance Criteria:**
- [ ] Run a mock Ralph iteration with skill candidate in output
- [ ] Verify skill file created at correct path
- [ ] Verify skill file has valid YAML frontmatter
- [ ] Verify skill file content matches input
- [ ] Verify Origin section populated correctly
- [ ] Clean up test artifacts after test

## Functional Requirements

- FR-1: prompt.md must instruct iterations to evaluate for skill extraction after verification passes
- FR-2: prompt.md must define the `<<<SKILL_CANDIDATE>>>` delimited block format
- FR-3: ralph.sh must detect `<<<SKILL_CANDIDATE>>>` blocks in iteration output
- FR-4: ralph.sh must parse category, name, description, and content from blocks
- FR-5: ralph.sh must validate category is one of: error-resolutions, patterns, workflows
- FR-6: ralph.sh must create `~/.claude/skills/ralph-learnings/[category]/` directories as needed
- FR-7: ralph.sh must write skills with YAML frontmatter containing only `name` and `description`
- FR-8: ralph.sh must append Origin section with extraction metadata
- FR-9: ralph.sh must not overwrite existing skills with the same name
- FR-10: Extraction must not break the main loop on any failure

## Non-Goals

- No manual `/claudeception` trigger (always automatic)
- No `--learn` or `--no-learn` flags (always enabled)
- No project-level skill storage (user-level only)
- No skill editing or deletion commands
- No skill quality scoring or ranking
- No web research during extraction (use existing knowledge only)

## Technical Considerations

- Use delimiter-based format (`<<<SKILL_CANDIDATE>>>`) for reliable bash parsing
- Avoid XML parsing with sed (fragile for multiline content)
- Skills follow standard SKILL.md format for Claude Code compatibility
- Origin section goes in content body, not YAML frontmatter (per writing-skills guide)
- Function should be defensive: any parsing failure → skip gracefully

## Success Metrics

- Skills extracted only when quality gates genuinely pass (low noise)
- Extracted skills are discoverable by Claude Code (valid format)
- Zero iteration failures caused by extraction logic
- Skills accumulate over time and provide value in future iterations

## Open Questions

- Should we add a way to view/list extracted skills from ralph.sh?
- Should skills have an expiration or relevance decay?
- Should we deduplicate skills that are semantically similar?
