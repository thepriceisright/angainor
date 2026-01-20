#!/usr/bin/env bash
# sync-to-project.sh - Sync Ralph files to a target project
#
# Usage: ./scripts/sync-to-project.sh <target-directory>
#
# This script copies all files necessary to run the Ralph loop:
#   - ralph.sh (main loop)
#   - prompt.md (agent instructions)
#   - skills/ (prd, ralph, read-transcript skills)
#   - scripts/migrate-prd.sh (PRD migration utility)
#
# It does NOT copy project-specific files (prd.json, progress.txt, etc.)

set -euo pipefail

# Get script directory (where claude-and-ralph repo is)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(dirname "$SCRIPT_DIR")"

# Check arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <target-directory>"
    echo ""
    echo "Example: $0 /workspace/weave"
    exit 1
fi

TARGET_DIR="$1"

# Validate target directory exists
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: Target directory does not exist: $TARGET_DIR"
    exit 1
fi

echo "Syncing Ralph files from: $SOURCE_DIR"
echo "                      to: $TARGET_DIR"
echo ""

# Files to copy
FILES_TO_COPY=(
    "ralph.sh"
    "prompt.md"
)

# Directories to copy
DIRS_TO_COPY=(
    "skills"
)

# Scripts to copy (into scripts/ subdirectory)
SCRIPTS_TO_COPY=(
    "migrate-prd.sh"
)

# Copy individual files
for file in "${FILES_TO_COPY[@]}"; do
    if [[ -f "$SOURCE_DIR/$file" ]]; then
        cp "$SOURCE_DIR/$file" "$TARGET_DIR/$file"
        echo "✓ Copied $file"
    else
        echo "⚠ Warning: $file not found in source"
    fi
done

# Copy directories
for dir in "${DIRS_TO_COPY[@]}"; do
    if [[ -d "$SOURCE_DIR/$dir" ]]; then
        # Remove existing directory to ensure clean copy
        rm -rf "$TARGET_DIR/$dir"
        cp -r "$SOURCE_DIR/$dir" "$TARGET_DIR/$dir"
        echo "✓ Copied $dir/"
    else
        echo "⚠ Warning: $dir/ not found in source"
    fi
done

# Copy scripts (ensure scripts/ directory exists)
mkdir -p "$TARGET_DIR/scripts"
for script in "${SCRIPTS_TO_COPY[@]}"; do
    if [[ -f "$SOURCE_DIR/scripts/$script" ]]; then
        cp "$SOURCE_DIR/scripts/$script" "$TARGET_DIR/scripts/$script"
        echo "✓ Copied scripts/$script"
    else
        echo "⚠ Warning: scripts/$script not found in source"
    fi
done

echo ""
echo "Sync complete!"
echo ""
echo "Files synced:"
ls -la "$TARGET_DIR/ralph.sh" "$TARGET_DIR/prompt.md" 2>/dev/null || true
echo ""
echo "To run Ralph in the target project:"
echo "  cd $TARGET_DIR"
echo "  ./ralph.sh [max_iterations]"
