# Ralph Profile Design

**Date:** 2026-01-20
**Status:** Approved

## Overview

Add a "Ralph Profile" to ralph.sh that configures a minimal plugin set for autonomous runs, integrates headless browser testing, and supports test coverage via separate PRD stories.

## Problem Statement

During autonomous Ralph runs, certain plugins interfere with the structured workflow:
- `automatic-code-review` - Distracts from story implementation
- `explanatory-output-style` - Changes output format, breaks verification parsing

Additionally, Ralph lacks:
- Browser verification capability for UI stories
- Test coverage for generated code

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Profile location | Built into ralph.sh | Self-contained, no external config files |
| Plugin management | CLI commands (`claude plugin disable/enable`) | Official API, cleaner than file manipulation |
| Plugin set | Core + Testing + Domain | Need git, browser testing, and infrastructure context |
| Browser testing | Headless with fallback to BLOCKED | Autonomous when possible, graceful degradation |
| Test coverage | Separate stories in PRDs | Keeps implementation focused, allows batching |

## Implementation

### 1. Plugin Management in ralph.sh

```bash
# Plugins to disable for autonomous runs
RALPH_DISABLE_PLUGINS=(
  "automatic-code-review@claude-skillz"
  "explanatory-output-style@claude-plugins-official"
)

configure_ralph_profile() {
  echo "Configuring Ralph profile (minimal plugins)..."
  for plugin in "${RALPH_DISABLE_PLUGINS[@]}"; do
    claude plugin disable "$plugin" 2>/dev/null || true
  done
}

restore_plugins() {
  echo "Restoring plugin configuration..."
  for plugin in "${RALPH_DISABLE_PLUGINS[@]}"; do
    claude plugin enable "$plugin" 2>/dev/null || true
  done
}

# At script start
configure_ralph_profile

# Trap ensures restore on exit (success, failure, or interrupt)
trap restore_plugins EXIT
```

### 2. Minimum Plugin Set

| Category | Plugins | Purpose |
|----------|---------|---------|
| Core | `commit-commands` | Git commits |
| Testing | `playwright` | Browser verification |
| Domain | `cloud-infrastructure`, `security-scanning` | AWS/infra context |
| Workflow | `superpowers` (subset) | TDD, debugging skills |

### 3. Browser Verification (prompt.md addition)

```markdown
## Browser Verification (Headless)

For stories with "Verify in browser" acceptance criteria:

1. Start the dev server if not running
2. Run headless Playwright test via playwright skill
3. Capture screenshot to `screenshots/[story-id].png`
4. Include screenshot path in verification evidence

If browser test fails after 2 attempts:
- Set story status to "blocked"
- Set blockedReason to browser test failure details
- Proceed to next story
```

Evidence format:
```
<verification>
Criterion: Verify in browser using dev-browser skill
Evidence: Headless Playwright test passed - screenshot at screenshots/US-049.png
Conclusion: SATISFIED
</verification>
```

### 4. Test Stories (prompt.md addition)

```markdown
## Test Stories

For stories with "Unit tests for..." in title:
- Use vitest or jest (detect from package.json)
- Mock external dependencies (AWS SDK, APIs)
- Place tests adjacent to source: `foo.ts` → `foo.test.ts`
- Run test command and include output in verification
```

Test story template for PRDs:
```json
{
  "id": "US-070",
  "title": "Unit Tests for ECS/ECR Clients",
  "description": "As a developer, I want unit tests for the AWS client classes so that regressions are caught.",
  "acceptanceCriteria": [
    "Tests for WeaveEcsClient (create, describe, delete cluster)",
    "Tests for WeaveEcrClient (create repo, push image)",
    "Mocked AWS SDK calls (no real AWS calls)",
    "Test coverage > 80% for target files",
    "All tests pass: npm test"
  ],
  "priority": 70,
  "passes": false
}
```

### 5. Screenshot Directory

```bash
SCREENSHOT_DIR="$SCRIPT_DIR/screenshots"
mkdir -p "$SCREENSHOT_DIR"
```

## Files to Modify

| File | Changes |
|------|---------|
| `ralph.sh` | Add plugin management functions, trap handler, screenshot dir setup |
| `prompt.md` | Add "Browser Verification (Headless)" section, "Test Stories" section |
| `CLAUDE.md` | Document Ralph profile behavior and minimum plugin set |

## Success Criteria

- [ ] ralph.sh disables interfering plugins at start
- [ ] ralph.sh restores plugins on exit (success, failure, or Ctrl+C)
- [ ] Browser stories can be verified via headless Playwright
- [ ] Failed browser tests result in BLOCKED status (not infinite retries)
- [ ] Test stories are documented and can be added to PRDs
- [ ] CLAUDE.md documents the Ralph profile behavior
