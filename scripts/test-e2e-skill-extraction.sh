#!/bin/bash
# End-to-end integration test for skill extraction (US-008)
# Verifies the complete flow from iteration output to skill file on disk

# shellcheck disable=SC2317  # Functions called via trap appear unreachable
# shellcheck disable=SC2034  # Variables used by eval'd function appear unused
# shellcheck disable=SC2016  # Single quotes intentional - we want literal strings

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_DIR="$(dirname "$SCRIPT_DIR")"

# Test configuration - use temp directory to avoid polluting real skill directory
TEST_SKILL_DIR=$(mktemp -d)
TEST_PRD_FILE=$(mktemp)
TEST_PASSED=0
TEST_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Cleanup function - removes all test artifacts
cleanup() {
  rm -rf "$TEST_SKILL_DIR"
  rm -f "$TEST_PRD_FILE"
}
trap cleanup EXIT

# Assertion helpers
assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" = "$actual" ]; then
    echo -e "${GREEN}✓${NC} $message"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗${NC} $message"
    echo "  Expected: $expected"
    echo "  Actual:   $actual"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if echo "$haystack" | grep -qF -- "$needle"; then
    echo -e "${GREEN}✓${NC} $message"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗${NC} $message"
    echo "  Expected to contain: $needle"
    echo "  Actual: $haystack"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if ! echo "$haystack" | grep -qF -- "$needle"; then
    echo -e "${GREEN}✓${NC} $message"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗${NC} $message"
    echo "  Expected NOT to contain: $needle"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi
}

assert_file_exists() {
  local file="$1"
  local message="$2"

  if [ -f "$file" ]; then
    echo -e "${GREEN}✓${NC} $message"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗${NC} $message"
    echo "  File not found: $file"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi
}

assert_dir_exists() {
  local dir="$1"
  local message="$2"

  if [ -d "$dir" ]; then
    echo -e "${GREEN}✓${NC} $message"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗${NC} $message"
    echo "  Directory not found: $dir"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi
}

# Create mock prd.json for testing
create_mock_prd() {
  cat > "$TEST_PRD_FILE" << 'EOF'
{
  "project": "TestProject",
  "branchName": "ralph/test-feature",
  "description": "Test project for e2e skill extraction",
  "userStories": []
}
EOF
}

# Source the write_skill_candidate function from ralph.sh with overrides
source_skill_function() {
  # Override SKILL_DIR and PRD_FILE for testing
  SKILL_DIR="$TEST_SKILL_DIR"
  PRD_FILE="$TEST_PRD_FILE"

  # Extract the write_skill_candidate function
  eval "$(sed -n '/^write_skill_candidate()/,/^}/p' "$RALPH_DIR/ralph.sh")"
}

# ============================================================
# TEST: End-to-end integration - complete flow verification
# ============================================================
test_e2e_integration() {
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  TEST: End-to-end integration"
  echo "═══════════════════════════════════════════════════════"

  # Setup
  create_mock_prd
  source_skill_function

  # Simulate a full Ralph iteration output with skill candidate
  local mock_iteration_output='
═══════════════════════════════════════════════════════
  Ralph Iteration 3 of 10
═══════════════════════════════════════════════════════

Starting implementation of US-003...

Reading prd.json and progress.txt...

## Implementation

Added new function to handle database migrations.
Changed 3 files:
- src/db/migrate.ts
- src/db/schema.ts
- tests/db/migrate.test.ts

## Verification

<verification>
Criterion: Typecheck passes
Evidence: Ran `npm run typecheck` - exit code 0, no errors
Conclusion: SATISFIED
</verification>

<verification>
Criterion: Unit tests pass
Evidence: Ran `npm test` - 42 tests passed, 0 failed
Conclusion: SATISFIED
</verification>

## Skill Extraction

This iteration discovered a reusable pattern for handling SQLite migrations.

<<<SKILL_CANDIDATE>>>
category: patterns
name: sqlite-migration-pattern
description: Use when implementing SQLite schema migrations with rollback support
content:
## Problem

When implementing database migrations in SQLite, you need to handle schema changes
while supporting rollback capabilities.

## Solution

Use a migrations table to track applied migrations and wrap changes in transactions:

```typescript
async function migrate(db: Database) {
  await db.exec(`
    CREATE TABLE IF NOT EXISTS migrations (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      applied_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
  `);

  const pending = await getPendingMigrations(db);
  for (const migration of pending) {
    await db.exec("BEGIN TRANSACTION");
    try {
      await migration.up(db);
      await db.run("INSERT INTO migrations (name) VALUES (?)", migration.name);
      await db.exec("COMMIT");
    } catch (error) {
      await db.exec("ROLLBACK");
      throw error;
    }
  }
}
```

## Verification

- Run `npm test -- --grep migration` to verify migration tests pass
- Check migrations table has correct entries after running
<<<END_SKILL_CANDIDATE>>>

Committing changes: feat: US-003 - Database migrations

Story US-003 complete.
'

  # Execute the skill extraction function
  local result
  result=$(write_skill_candidate "$mock_iteration_output" "US-003" 2>&1) || true

  # Verify function outputs success message
  assert_contains "$result" "Extracted skill: patterns/sqlite-migration-pattern.md" \
    "Function outputs extraction success message"

  # Verify directory structure created
  assert_dir_exists "$TEST_SKILL_DIR/patterns" \
    "Patterns category directory created"

  # Verify skill file created at correct path
  local expected_file="$TEST_SKILL_DIR/patterns/sqlite-migration-pattern.md"
  assert_file_exists "$expected_file" \
    "Skill file created at correct path"

  # Read the created skill file
  local skill_content
  skill_content=$(cat "$expected_file")

  # Verify YAML frontmatter is valid
  echo ""
  echo "  Checking YAML frontmatter..."

  local first_line
  first_line=$(echo "$skill_content" | head -1)
  assert_equals "---" "$first_line" \
    "File starts with YAML frontmatter delimiter"

  # Check frontmatter has name field
  assert_contains "$skill_content" "name: sqlite-migration-pattern" \
    "Frontmatter contains correct name"

  # Check frontmatter has description field
  assert_contains "$skill_content" "description: Use when implementing SQLite schema migrations with rollback support" \
    "Frontmatter contains correct description"

  # Check frontmatter does NOT contain category (should only be name and description)
  local frontmatter
  frontmatter=$(echo "$skill_content" | sed -n '2,/^---$/p' | head -n -1)
  assert_not_contains "$frontmatter" "category:" \
    "Frontmatter correctly omits category field"

  # Verify content matches input
  echo ""
  echo "  Checking content preservation..."

  assert_contains "$skill_content" "## Problem" \
    "Content has Problem section"
  assert_contains "$skill_content" "## Solution" \
    "Content has Solution section"
  assert_contains "$skill_content" "## Verification" \
    "Content has Verification section"
  assert_contains "$skill_content" "CREATE TABLE IF NOT EXISTS migrations" \
    "SQL code preserved in content"
  assert_contains "$skill_content" "BEGIN TRANSACTION" \
    "Transaction handling code preserved"
  assert_contains "$skill_content" '```typescript' \
    "TypeScript code block preserved"

  # Verify Origin section populated correctly
  echo ""
  echo "  Checking Origin section..."

  assert_contains "$skill_content" "## Origin" \
    "File has Origin section"
  assert_contains "$skill_content" "Story: US-003" \
    "Origin has correct story ID"
  assert_contains "$skill_content" "Project: TestProject" \
    "Origin has project name from prd.json"
  assert_contains "$skill_content" "Extracted:" \
    "Origin has extraction timestamp"

  # Verify timestamp format (ISO 8601)
  if echo "$skill_content" | grep -qE "Extracted: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"; then
    echo -e "${GREEN}✓${NC} Extraction timestamp is in ISO 8601 format"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗${NC} Extraction timestamp should be in ISO 8601 format"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi
}

# ============================================================
# TEST: Verify cleanup removes test artifacts
# ============================================================
test_cleanup() {
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  TEST: Cleanup verification"
  echo "═══════════════════════════════════════════════════════"

  # Verify test directories exist before cleanup (they should from previous test)
  if [ -d "$TEST_SKILL_DIR" ]; then
    echo -e "${GREEN}✓${NC} Test skill directory exists before cleanup"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗${NC} Test skill directory should exist before cleanup"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi

  if [ -f "$TEST_PRD_FILE" ]; then
    echo -e "${GREEN}✓${NC} Test PRD file exists before cleanup"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗${NC} Test PRD file should exist before cleanup"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi

  # Note: Actual cleanup happens on script exit via trap
  echo "  (Cleanup will occur on script exit via trap)"
}

# ============================================================
# TEST: Multiple skill categories in single iteration
# ============================================================
test_multiple_categories() {
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  TEST: Skill files in different categories"
  echo "═══════════════════════════════════════════════════════"

  # Reset test directory
  rm -rf "$TEST_SKILL_DIR"
  mkdir -p "$TEST_SKILL_DIR"
  create_mock_prd
  source_skill_function

  # Test error-resolutions category
  local error_output='<<<SKILL_CANDIDATE>>>
category: error-resolutions
name: fix-node-heap-oom
description: Use when encountering Node.js heap out of memory errors
content:
## Problem
Node.js throws "FATAL ERROR: CALL_AND_RETRY_LAST Allocation failed - JavaScript heap out of memory"

## Solution
Increase Node.js memory limit:
```bash
export NODE_OPTIONS="--max-old-space-size=4096"
```

## Verification
Run the failing command again and verify it completes successfully.
<<<END_SKILL_CANDIDATE>>>'

  write_skill_candidate "$error_output" "US-E2E-1" > /dev/null 2>&1 || true

  assert_dir_exists "$TEST_SKILL_DIR/error-resolutions" \
    "error-resolutions category directory created"
  assert_file_exists "$TEST_SKILL_DIR/error-resolutions/fix-node-heap-oom.md" \
    "Skill file created in error-resolutions"

  # Test workflows category
  local workflow_output='<<<SKILL_CANDIDATE>>>
category: workflows
name: tdd-red-green-refactor
description: Use when implementing features using test-driven development
content:
## Problem
Need a structured approach to implementing features with tests.

## Solution
Follow the red-green-refactor cycle:
1. Write a failing test (red)
2. Write minimal code to pass (green)
3. Refactor while keeping tests passing

## Verification
All tests should pass after each green and refactor phase.
<<<END_SKILL_CANDIDATE>>>'

  write_skill_candidate "$workflow_output" "US-E2E-2" > /dev/null 2>&1 || true

  assert_dir_exists "$TEST_SKILL_DIR/workflows" \
    "workflows category directory created"
  assert_file_exists "$TEST_SKILL_DIR/workflows/tdd-red-green-refactor.md" \
    "Skill file created in workflows"

  # Verify both files have correct structure
  local error_content workflow_content
  error_content=$(cat "$TEST_SKILL_DIR/error-resolutions/fix-node-heap-oom.md")
  workflow_content=$(cat "$TEST_SKILL_DIR/workflows/tdd-red-green-refactor.md")

  assert_contains "$error_content" "Story: US-E2E-1" \
    "error-resolutions skill has correct story ID"
  assert_contains "$workflow_content" "Story: US-E2E-2" \
    "workflows skill has correct story ID"
}

# ============================================================
# Run all tests
# ============================================================
echo "╔═══════════════════════════════════════════════════════╗"
echo "║  End-to-End Skill Extraction Test (US-008)            ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "Test skill directory: $TEST_SKILL_DIR"
echo "Test PRD file: $TEST_PRD_FILE"

test_e2e_integration
test_multiple_categories
test_cleanup

# Summary
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  TEST SUMMARY"
echo "═══════════════════════════════════════════════════════"
echo -e "  Passed: ${GREEN}$TEST_PASSED${NC}"
echo -e "  Failed: ${RED}$TEST_FAILED${NC}"
echo "═══════════════════════════════════════════════════════"

if [ "$TEST_FAILED" -gt 0 ]; then
  exit 1
fi

echo ""
echo "All tests passed!"
exit 0
