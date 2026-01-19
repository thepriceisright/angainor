#!/usr/bin/env bash
# migrate-prd.sh - Migrate prd.json to new format with status/attempts fields
#
# Usage: ./scripts/migrate-prd.sh [path/to/prd.json]
#        Default: prd.json in current directory
#
# This script:
# - Adds status: 'pending' to stories where passes: false
# - Adds status: 'passed' to stories where passes: true
# - Adds attempts: 0 to all stories without it
# - Preserves all existing fields
# - Creates backup before modifying (prd.json.bak)
# - Is idempotent (safe to run multiple times)

set -euo pipefail

# Default to prd.json in current directory
PRD_FILE="${1:-prd.json}"

# Check if file exists
if [[ ! -f "$PRD_FILE" ]]; then
    echo "Error: File not found: $PRD_FILE" >&2
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed" >&2
    exit 1
fi

# Validate JSON
if ! jq empty "$PRD_FILE" 2>/dev/null; then
    echo "Error: Invalid JSON in $PRD_FILE" >&2
    exit 1
fi

# Create backup
BACKUP_FILE="${PRD_FILE}.bak"
cp "$PRD_FILE" "$BACKUP_FILE"
echo "Created backup: $BACKUP_FILE"

# Migrate each story:
# - Add status based on passes value (only if status doesn't exist)
# - Add attempts: 0 if it doesn't exist
# The script preserves all existing fields including passes for backward compatibility
jq '
.userStories = [.userStories[] |
    # Add status if not present
    if has("status") then .
    elif .passes == true then . + {status: "passed"}
    else . + {status: "pending"}
    end |
    # Add attempts if not present (1 for passed, 0 for pending)
    if has("attempts") then .
    elif .status == "passed" then . + {attempts: 1}
    else . + {attempts: 0}
    end
]
' "$BACKUP_FILE" > "$PRD_FILE"

echo "Migration complete: $PRD_FILE"
echo "Stories migrated:"
jq -r '.userStories[] | "  \(.id): status=\(.status), attempts=\(.attempts)"' "$PRD_FILE"
