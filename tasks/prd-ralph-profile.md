# PRD: Ralph Profile

## Introduction

Add a "Ralph Profile" to the Ralph autonomous agent loop that configures a minimal plugin set for autonomous runs, integrates headless browser testing for UI verification, and documents test coverage patterns for PRDs.

During autonomous Ralph runs, certain plugins (`automatic-code-review`, `explanatory-output-style`) interfere with the structured workflow by distracting from story implementation or breaking verification parsing. Additionally, Ralph currently lacks browser verification capability for UI stories and guidance on test coverage.

## Goals

- Disable interfering plugins automatically at Ralph startup
- Restore plugins reliably on exit (success, failure, or Ctrl+C)
- Enable headless Playwright browser testing for UI story verification
- Provide graceful degradation (BLOCKED status) when browser tests fail
- Document test story patterns for future PRDs
- Keep all changes self-contained in the Ralph system (no external config files)

## User Stories

### US-001: Plugin Management Functions in ralph.sh
**Description:** As a Ralph operator, I want ralph.sh to manage plugin state so that interfering plugins are disabled during autonomous runs.

**Acceptance Criteria:**
- [ ] Add `RALPH_DISABLE_PLUGINS` array with plugins to disable: `automatic-code-review@claude-skillz`, `explanatory-output-style@claude-plugins-official`
- [ ] Add `configure_ralph_profile()` function that disables each plugin via `claude plugin disable`
- [ ] Add `restore_plugins()` function that re-enables each plugin via `claude plugin enable`
- [ ] Functions handle missing plugins gracefully (no errors if plugin not installed)
- [ ] Script passes shellcheck

### US-002: Plugin Restore on Exit in ralph.sh
**Description:** As a Ralph operator, I want plugins restored when Ralph exits so that my normal Claude Code environment is preserved.

**Acceptance Criteria:**
- [ ] `trap restore_plugins EXIT` ensures cleanup on normal exit
- [ ] Plugins restored on Ctrl+C interrupt (SIGINT)
- [ ] Plugins restored on script error (set -e failure)
- [ ] `configure_ralph_profile` called at script start before main loop
- [ ] Script passes shellcheck

### US-003: Screenshot Directory Setup in ralph.sh
**Description:** As a Ralph operator, I want a screenshots directory so that browser verification evidence is captured.

**Acceptance Criteria:**
- [ ] Add `SCREENSHOT_DIR="$SCRIPT_DIR/screenshots"` variable
- [ ] Create directory with `mkdir -p "$SCREENSHOT_DIR"` at startup
- [ ] Add `screenshots/` to `.gitignore` (or document as gitignored)
- [ ] Script passes shellcheck

### US-004: Browser Verification Section in prompt.md
**Description:** As a Ralph agent, I need instructions for headless browser testing so that I can verify UI stories autonomously.

**Acceptance Criteria:**
- [ ] Add "Browser Verification (Headless)" section to prompt.md
- [ ] Instructions cover: detecting "Verify in browser" criteria, running headless Playwright, capturing screenshots
- [ ] Screenshot path format: `screenshots/[story-id].png`
- [ ] Failure handling: 2 attempts, then mark story as BLOCKED with reason
- [ ] Verification evidence format documented with example
- [ ] Section is under 30 lines

### US-005: Test Stories Section in prompt.md
**Description:** As a Ralph agent, I need instructions for implementing test stories so that I can write unit tests when PRDs include them.

**Acceptance Criteria:**
- [ ] Add "Test Stories" section to prompt.md
- [ ] Instructions cover: detecting test framework (vitest/jest), mocking external dependencies, test file placement
- [ ] Test file naming convention: `foo.ts` → `foo.test.ts`
- [ ] Verification must include test command output
- [ ] Section is under 20 lines

### US-006: Document Ralph Profile in CLAUDE.md
**Description:** As a developer working on Ralph, I want CLAUDE.md to document the Ralph Profile so that the behavior is understood.

**Acceptance Criteria:**
- [ ] Add "Ralph Profile" subsection under appropriate section
- [ ] Document which plugins are disabled and why
- [ ] Document plugin restore behavior on exit
- [ ] Document minimum plugin set (Core, Testing, Domain categories)
- [ ] Document the flexible verification check (accepts `<verification>` OR `✅`)
- [ ] Keep additions under 25 lines

## Functional Requirements

- FR-1: ralph.sh MUST disable `automatic-code-review@claude-skillz` at startup
- FR-2: ralph.sh MUST disable `explanatory-output-style@claude-plugins-official` at startup
- FR-3: ralph.sh MUST restore disabled plugins on any exit (success, failure, interrupt)
- FR-4: ralph.sh MUST create `screenshots/` directory for browser test evidence
- FR-5: prompt.md MUST instruct Claude to use headless Playwright for "Verify in browser" criteria
- FR-6: prompt.md MUST instruct Claude to mark stories as BLOCKED after 2 failed browser attempts
- FR-7: prompt.md MUST instruct Claude on test story implementation patterns
- FR-8: CLAUDE.md MUST document the Ralph Profile behavior

## Non-Goals

- No external profile configuration files (everything in ralph.sh)
- No changes to prd.json schema (test stories use existing format)
- No automatic test generation for existing stories (tests are separate stories in PRDs)
- No headed browser mode (always headless for autonomous runs)
- No Playwright installation in ralph.sh (assumes playwright skill is installed)

## Technical Considerations

- Use `claude plugin disable/enable` CLI commands (official API)
- Use bash trap for reliable cleanup on all exit paths
- Playwright skill already installed at `~/.claude/plugins/marketplaces/playwright-skill`
- Browser tests write to `/tmp/playwright-test-*.js` per playwright skill conventions
- Screenshots stored in project's `screenshots/` directory (not /tmp)

## Success Metrics

- Zero verification failures due to plugin interference in new Ralph runs
- UI stories can be verified autonomously via headless browser
- Failed browser tests result in BLOCKED (not infinite retries)
- Plugins always restored after Ralph exits (no permanent state change)

## Open Questions

None - design was validated through brainstorming session.
