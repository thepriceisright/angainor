#!/bin/bash
# Test script for skill extraction functionality (US-005, US-006)
# Tests valid input scenarios and edge cases for write_skill_candidate function

# shellcheck disable=SC2317  # Functions called via trap appear unreachable
# shellcheck disable=SC2034  # Variables used by eval'd function appear unused
# shellcheck disable=SC2016  # Single quotes intentional - we want literal <<<

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_DIR="$(dirname "$SCRIPT_DIR")"

# Test configuration
TEST_SKILL_DIR=$(mktemp -d)
TEST_PASSED=0
TEST_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Cleanup function
cleanup() {
  rm -rf "$TEST_SKILL_DIR"
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

assert_file_not_exists() {
  local file="$1"
  local message="$2"

  if [ ! -f "$file" ]; then
    echo -e "${GREEN}✓${NC} $message"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗${NC} $message"
    echo "  File should not exist: $file"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" -eq "$actual" ]; then
    echo -e "${GREEN}✓${NC} $message"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗${NC} $message"
    echo "  Expected exit code: $expected"
    echo "  Actual exit code: $actual"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi
}

assert_output_empty() {
  local output="$1"
  local message="$2"

  if [ -z "$output" ]; then
    echo -e "${GREEN}✓${NC} $message"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗${NC} $message"
    echo "  Expected empty output"
    echo "  Actual: $output"
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

# Source the write_skill_candidate function from ralph.sh
# We need to extract and source just the function, overriding SKILL_DIR
source_skill_function() {
  # Override SKILL_DIR for testing
  SKILL_DIR="$TEST_SKILL_DIR"
  PRD_FILE="$RALPH_DIR/prd.json"

  # Extract the write_skill_candidate function
  eval "$(sed -n '/^write_skill_candidate()/,/^}/p' "$RALPH_DIR/ralph.sh")"
}

# ============================================================
# TEST: Extract all fields correctly from valid skill candidate
# ============================================================
test_valid_extraction() {
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  TEST: Valid skill extraction"
  echo "═══════════════════════════════════════════════════════"

  source_skill_function

  local test_output='Some iteration output before...

<<<SKILL_CANDIDATE>>>
category: error-resolutions
name: fix-vitest-mock-error
description: Use when encountering "vi is not defined" error in Vitest tests
content:
## Problem

When running Vitest tests, you get "vi is not defined" error.

## Solution

Add the globals option to vitest.config.ts:

```typescript
export default defineConfig({
  test: {
    globals: true,
  },
});
```

## Verification

Run `npm test` and verify tests pass without "vi is not defined" errors.
<<<END_SKILL_CANDIDATE>>>

More output after...'

  local result
  result=$(write_skill_candidate "$test_output" "US-TEST" 2>&1) || true

  # Check function returned success message
  assert_contains "$result" "Extracted skill: error-resolutions/fix-vitest-mock-error.md" \
    "Function outputs success message"

  # Check directory was created
  assert_dir_exists "$TEST_SKILL_DIR/error-resolutions" \
    "Category directory created"

  # Check file was created
  assert_file_exists "$TEST_SKILL_DIR/error-resolutions/fix-vitest-mock-error.md" \
    "Skill file created"

  # Read the created file
  local file_content
  file_content=$(cat "$TEST_SKILL_DIR/error-resolutions/fix-vitest-mock-error.md")

  # Check YAML frontmatter
  assert_contains "$file_content" "---" \
    "File has YAML frontmatter delimiters"
  assert_contains "$file_content" "name: fix-vitest-mock-error" \
    "File has correct name in frontmatter"
  assert_contains "$file_content" 'description: Use when encountering "vi is not defined" error in Vitest tests' \
    "File has correct description in frontmatter"

  # Check content preservation
  assert_contains "$file_content" "## Problem" \
    "Content has Problem section"
  assert_contains "$file_content" "## Solution" \
    "Content has Solution section"
  assert_contains "$file_content" "## Verification" \
    "Content has Verification section"
  assert_contains "$file_content" "globals: true" \
    "Content preserves code example"

  # Check Origin section
  assert_contains "$file_content" "## Origin" \
    "File has Origin section"
  assert_contains "$file_content" "Story: US-TEST" \
    "Origin has correct story ID"
  assert_contains "$file_content" "Project:" \
    "Origin has project field"
  assert_contains "$file_content" "Extracted:" \
    "Origin has extraction timestamp"
}

# ============================================================
# TEST: Creates correct directory structure for each category
# ============================================================
test_directory_structure() {
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  TEST: Directory structure creation"
  echo "═══════════════════════════════════════════════════════"

  # Reset test directory
  rm -rf "$TEST_SKILL_DIR"
  mkdir -p "$TEST_SKILL_DIR"
  source_skill_function

  # Test patterns category
  local patterns_output='<<<SKILL_CANDIDATE>>>
category: patterns
name: test-patterns-skill
description: Use when testing patterns category
content:
Test content for patterns category.
<<<END_SKILL_CANDIDATE>>>'

  write_skill_candidate "$patterns_output" "US-TEST" > /dev/null 2>&1 || true
  assert_dir_exists "$TEST_SKILL_DIR/patterns" \
    "Patterns category directory created"
  assert_file_exists "$TEST_SKILL_DIR/patterns/test-patterns-skill.md" \
    "Skill file created in patterns directory"

  # Test workflows category
  local workflows_output='<<<SKILL_CANDIDATE>>>
category: workflows
name: test-workflows-skill
description: Use when testing workflows category
content:
Test content for workflows category.
<<<END_SKILL_CANDIDATE>>>'

  write_skill_candidate "$workflows_output" "US-TEST" > /dev/null 2>&1 || true
  assert_dir_exists "$TEST_SKILL_DIR/workflows" \
    "Workflows category directory created"
  assert_file_exists "$TEST_SKILL_DIR/workflows/test-workflows-skill.md" \
    "Skill file created in workflows directory"
}

# ============================================================
# TEST: YAML frontmatter is valid
# ============================================================
test_yaml_frontmatter() {
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  TEST: Valid YAML frontmatter"
  echo "═══════════════════════════════════════════════════════"

  # Reset test directory
  rm -rf "$TEST_SKILL_DIR"
  mkdir -p "$TEST_SKILL_DIR"
  source_skill_function

  local test_output='<<<SKILL_CANDIDATE>>>
category: error-resolutions
name: yaml-test-skill
description: Use when testing YAML frontmatter format
content:
Content body here.
<<<END_SKILL_CANDIDATE>>>'

  write_skill_candidate "$test_output" "US-YAML" > /dev/null 2>&1 || true

  local file_content
  file_content=$(cat "$TEST_SKILL_DIR/error-resolutions/yaml-test-skill.md")

  # Check frontmatter structure (should start with --- and have closing ---)
  local first_line
  first_line=$(echo "$file_content" | head -1)
  assert_equals "---" "$first_line" \
    "File starts with YAML frontmatter delimiter"

  # Check that frontmatter has exactly name and description fields
  local frontmatter
  frontmatter=$(echo "$file_content" | sed -n '2,/^---$/p' | head -n -1)

  local field_count
  field_count=$(echo "$frontmatter" | grep -c ":" || echo "0")
  assert_equals "2" "$field_count" \
    "Frontmatter has exactly 2 fields (name and description)"

  # Check no extra fields like 'triggers' or 'category'
  if echo "$frontmatter" | grep -q "category:"; then
    echo -e "${RED}✗${NC} Frontmatter should NOT contain category field"
    TEST_FAILED=$((TEST_FAILED + 1))
  else
    echo -e "${GREEN}✓${NC} Frontmatter correctly omits category field"
    TEST_PASSED=$((TEST_PASSED + 1))
  fi
}

# ============================================================
# TEST: Multiline content is preserved correctly
# ============================================================
test_multiline_content() {
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  TEST: Multiline content preservation"
  echo "═══════════════════════════════════════════════════════"

  # Reset test directory
  rm -rf "$TEST_SKILL_DIR"
  mkdir -p "$TEST_SKILL_DIR"
  source_skill_function

  local test_output='<<<SKILL_CANDIDATE>>>
category: patterns
name: multiline-test-skill
description: Use when testing multiline content
content:
## Problem

This is a multi-paragraph problem description.

It spans multiple lines and paragraphs.

## Solution

1. First step
2. Second step
3. Third step

```bash
# This is a code block
echo "Hello World"
for i in 1 2 3; do
  echo $i
done
```

## Example

```typescript
interface User {
  id: string;
  name: string;
}

function getUser(id: string): User {
  return { id, name: "Test" };
}
```

## Verification

Run the following:
- Check A
- Check B
- Check C
<<<END_SKILL_CANDIDATE>>>'

  write_skill_candidate "$test_output" "US-MULTI" > /dev/null 2>&1 || true

  local file_content
  file_content=$(cat "$TEST_SKILL_DIR/patterns/multiline-test-skill.md")

  # Check multiple sections are preserved
  assert_contains "$file_content" "## Problem" \
    "Problem section preserved"
  assert_contains "$file_content" "## Solution" \
    "Solution section preserved"
  assert_contains "$file_content" "## Example" \
    "Example section preserved"
  assert_contains "$file_content" "## Verification" \
    "Verification section preserved"

  # Check code blocks are preserved
  assert_contains "$file_content" '```bash' \
    "Bash code block preserved"
  assert_contains "$file_content" '```typescript' \
    "TypeScript code block preserved"

  # Check numbered list is preserved
  assert_contains "$file_content" "1. First step" \
    "Numbered list preserved"

  # Check bulleted list is preserved
  assert_contains "$file_content" "- Check A" \
    "Bulleted list preserved"

  # Check that multi-paragraph text is preserved
  assert_contains "$file_content" "It spans multiple lines and paragraphs." \
    "Multi-paragraph content preserved"

  # Check interface definition is preserved
  assert_contains "$file_content" "interface User {" \
    "TypeScript interface preserved"
}

# ============================================================
# EDGE CASE TESTS (US-006)
# ============================================================

# ============================================================
# TEST: Missing skill candidate block returns 0, no output
# ============================================================
test_missing_block() {
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  TEST: Missing skill candidate block"
  echo "═══════════════════════════════════════════════════════"

  # Reset test directory
  rm -rf "$TEST_SKILL_DIR"
  mkdir -p "$TEST_SKILL_DIR"
  source_skill_function

  local test_output='This is just regular iteration output.
No skill candidate block here.
Just normal text about what was implemented.'

  local result
  local exit_code
  result=$(write_skill_candidate "$test_output" "US-NONE" 2>&1)
  exit_code=$?

  assert_exit_code 0 "$exit_code" \
    "Function returns 0 when no skill block present"
  assert_output_empty "$result" \
    "No output when skill block is missing"

  # Verify no directories were created
  local dir_count
  dir_count=$(find "$TEST_SKILL_DIR" -mindepth 1 -type d 2>/dev/null | wc -l)
  assert_equals "0" "$dir_count" \
    "No directories created when no skill block"
}

# ============================================================
# TEST: Malformed block (missing fields) shows warning
# ============================================================
test_malformed_block() {
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  TEST: Malformed block (missing fields)"
  echo "═══════════════════════════════════════════════════════"

  # Reset test directory
  rm -rf "$TEST_SKILL_DIR"
  mkdir -p "$TEST_SKILL_DIR"
  source_skill_function

  # Test missing category
  local test_missing_category='<<<SKILL_CANDIDATE>>>
name: missing-category-skill
description: Test skill missing category
content:
Some content here.
<<<END_SKILL_CANDIDATE>>>'

  local result
  local exit_code
  result=$(write_skill_candidate "$test_missing_category" "US-MALFORMED" 2>&1) && exit_code=0 || exit_code=$?

  assert_equals 1 "$exit_code" \
    "Returns non-zero when category missing"
  assert_contains "$result" "missing required field: category" \
    "Warning message mentions missing category"
  assert_file_not_exists "$TEST_SKILL_DIR/error-resolutions/missing-category-skill.md" \
    "No file created when category missing"

  # Test missing name
  local test_missing_name='<<<SKILL_CANDIDATE>>>
category: patterns
description: Test skill missing name
content:
Some content here.
<<<END_SKILL_CANDIDATE>>>'

  result=$(write_skill_candidate "$test_missing_name" "US-MALFORMED" 2>&1) && exit_code=0 || exit_code=$?

  assert_equals 1 "$exit_code" \
    "Returns non-zero when name missing"
  assert_contains "$result" "missing required field: name" \
    "Warning message mentions missing name"

  # Test missing description
  local test_missing_description='<<<SKILL_CANDIDATE>>>
category: patterns
name: missing-description-skill
content:
Some content here.
<<<END_SKILL_CANDIDATE>>>'

  result=$(write_skill_candidate "$test_missing_description" "US-MALFORMED" 2>&1) && exit_code=0 || exit_code=$?

  assert_equals 1 "$exit_code" \
    "Returns non-zero when description missing"
  assert_contains "$result" "missing required field: description" \
    "Warning message mentions missing description"

  # Test missing content
  local test_missing_content='<<<SKILL_CANDIDATE>>>
category: patterns
name: missing-content-skill
description: Test skill missing content
<<<END_SKILL_CANDIDATE>>>'

  result=$(write_skill_candidate "$test_missing_content" "US-MALFORMED" 2>&1) && exit_code=0 || exit_code=$?

  assert_equals 1 "$exit_code" \
    "Returns non-zero when content missing"
  assert_contains "$result" "missing required field: content" \
    "Warning message mentions missing content"

  # Test missing end delimiter
  local test_missing_end='<<<SKILL_CANDIDATE>>>
category: patterns
name: missing-end-skill
description: Test skill missing end delimiter
content:
Some content here but no end delimiter.'

  result=$(write_skill_candidate "$test_missing_end" "US-MALFORMED" 2>&1) && exit_code=0 || exit_code=$?

  assert_equals 1 "$exit_code" \
    "Returns non-zero when end delimiter missing"
  # When end delimiter is missing, content extraction fails - resulting in "missing content" warning
  assert_contains "$result" "⚠" \
    "Warning shown when end delimiter missing"
  assert_file_not_exists "$TEST_SKILL_DIR/patterns/missing-end-skill.md" \
    "No file created when end delimiter missing"
}

# ============================================================
# TEST: Invalid category shows warning, no file created
# ============================================================
test_invalid_category() {
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  TEST: Invalid category"
  echo "═══════════════════════════════════════════════════════"

  # Reset test directory
  rm -rf "$TEST_SKILL_DIR"
  mkdir -p "$TEST_SKILL_DIR"
  source_skill_function

  local test_bad_category='<<<SKILL_CANDIDATE>>>
category: invalid-category
name: bad-category-skill
description: Use when testing invalid category handling
content:
This skill has an invalid category.
<<<END_SKILL_CANDIDATE>>>'

  local result
  local exit_code
  result=$(write_skill_candidate "$test_bad_category" "US-BADCAT" 2>&1) && exit_code=0 || exit_code=$?

  assert_equals 1 "$exit_code" \
    "Returns non-zero for invalid category"
  assert_contains "$result" "invalid category" \
    "Warning message mentions invalid category"
  assert_contains "$result" "invalid-category" \
    "Warning shows the attempted category"
  assert_contains "$result" "error-resolutions, patterns, workflows" \
    "Warning shows valid categories"
  assert_file_not_exists "$TEST_SKILL_DIR/invalid-category/bad-category-skill.md" \
    "No file created for invalid category"

  # Test another invalid category
  local test_typo_category='<<<SKILL_CANDIDATE>>>
category: pattern
name: typo-category-skill
description: Use when testing typo in category
content:
This has a typo in the category (pattern vs patterns).
<<<END_SKILL_CANDIDATE>>>'

  result=$(write_skill_candidate "$test_typo_category" "US-TYPO" 2>&1) && exit_code=0 || exit_code=$?

  assert_equals 1 "$exit_code" \
    "Returns non-zero for typo in category (pattern vs patterns)"
  assert_contains "$result" "invalid category: pattern" \
    "Warning shows the typo category"
}

# ============================================================
# TEST: Duplicate skill name shows warning, no overwrite
# ============================================================
test_duplicate_skill() {
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  TEST: Duplicate skill name"
  echo "═══════════════════════════════════════════════════════"

  # Reset test directory
  rm -rf "$TEST_SKILL_DIR"
  mkdir -p "$TEST_SKILL_DIR"
  source_skill_function

  # First, create a skill
  local first_skill='<<<SKILL_CANDIDATE>>>
category: error-resolutions
name: duplicate-test-skill
description: Use when testing duplicate detection
content:
Original content - this should NOT be overwritten.
<<<END_SKILL_CANDIDATE>>>'

  local result
  result=$(write_skill_candidate "$first_skill" "US-FIRST" 2>&1)

  assert_contains "$result" "Extracted skill:" \
    "First skill created successfully"
  assert_file_exists "$TEST_SKILL_DIR/error-resolutions/duplicate-test-skill.md" \
    "First skill file exists"

  # Capture original content
  local original_content
  original_content=$(cat "$TEST_SKILL_DIR/error-resolutions/duplicate-test-skill.md")

  # Now try to create a skill with the same name
  local second_skill='<<<SKILL_CANDIDATE>>>
category: error-resolutions
name: duplicate-test-skill
description: Use when testing - DUPLICATE ATTEMPT
content:
New content that should NOT replace the original.
<<<END_SKILL_CANDIDATE>>>'

  local exit_code
  result=$(write_skill_candidate "$second_skill" "US-SECOND" 2>&1) && exit_code=0 || exit_code=$?

  assert_equals 1 "$exit_code" \
    "Returns non-zero for duplicate skill"
  assert_contains "$result" "already exists" \
    "Warning mentions skill already exists"
  assert_contains "$result" "skipping" \
    "Warning mentions skipping"

  # Verify original content was not overwritten
  local current_content
  current_content=$(cat "$TEST_SKILL_DIR/error-resolutions/duplicate-test-skill.md")

  if [ "$original_content" = "$current_content" ]; then
    echo -e "${GREEN}✓${NC} Original file content preserved (not overwritten)"
    TEST_PASSED=$((TEST_PASSED + 1))
  else
    echo -e "${RED}✗${NC} Original file was overwritten!"
    TEST_FAILED=$((TEST_FAILED + 1))
  fi

  # Verify original story ID is preserved
  assert_contains "$current_content" "Story: US-FIRST" \
    "Original story ID preserved in file"
}

# ============================================================
# Run all tests
# ============================================================
echo "╔═══════════════════════════════════════════════════════╗"
echo "║  Ralph Skill Extraction Tests (US-005, US-006)        ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "Test skill directory: $TEST_SKILL_DIR"

test_valid_extraction
test_directory_structure
test_yaml_frontmatter
test_multiline_content

# Edge case tests (US-006)
test_missing_block
test_malformed_block
test_invalid_category
test_duplicate_skill

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
