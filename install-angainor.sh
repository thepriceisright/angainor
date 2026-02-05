#!/usr/bin/env bash
#
# install-angainor.sh - Install Angainor (autonomous AI agent loop) into your project
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/thepriceisright/angainor/main/install-angainor.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/thepriceisright/angainor/main/install-angainor.sh | bash -s /path/to/project
#   ./install-angainor.sh [target-directory]
#
# This script downloads and configures Angainor for running autonomous PRD execution
# and goal-seeking Objective mode.
#

set -euo pipefail

# Configuration
REPO_URL="https://raw.githubusercontent.com/thepriceisright/angainor/main"
TARGET_DIR="${1:-.}"
ANGAINOR_DIR="${TARGET_DIR}/.angainor"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check for required tools
check_dependencies() {
    log_info "Checking dependencies..."

    local missing=()

    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        missing+=("curl or wget")
    fi

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if ! command -v git &> /dev/null; then
        missing+=("git")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing[*]}"
        log_error "Please install them and try again."
        exit 1
    fi

    log_success "Dependencies OK"
}

# Validate Claude Code CLI installation
# Returns 0 even on failure (installation continues with warnings)
validate_claude_cli() {
    log_info "Checking Claude Code CLI..."

    # Check if CLI exists
    if ! command -v claude &> /dev/null; then
        log_warn "Claude Code CLI not found."
        log_warn "  Install: npm install -g @anthropic-ai/claude-code"
        log_warn "  Angainor files will be installed, but you'll need Claude CLI to run it."
        return 0
    fi

    # Check version
    local version
    version=$(claude --version 2>/dev/null | head -1 || echo "unknown")
    local ver_num
    ver_num=$(echo "$version" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || echo "")

    if [ -z "$ver_num" ]; then
        log_warn "Could not parse Claude CLI version from: $version"
        log_warn "  Angainor requires version 2.1.20 or later."
        return 0
    fi

    log_success "Claude CLI version: $ver_num"

    local major minor patch
    major=$(echo "$ver_num" | cut -d. -f1)
    minor=$(echo "$ver_num" | cut -d. -f2)
    patch=$(echo "$ver_num" | cut -d. -f3)

    local min_version="2.1.20"
    if [ "$major" -lt 2 ] 2>/dev/null || \
       { [ "$major" -eq 2 ] && [ "$minor" -lt 1 ]; } 2>/dev/null || \
       { [ "$major" -eq 2 ] && [ "$minor" -eq 1 ] && [ "$patch" -lt 20 ]; } 2>/dev/null; then
        log_error "Claude CLI $ver_num is older than required minimum ($min_version)"
        log_error "  Run 'claude update' to update."
        log_error "  Angainor may not work correctly with this version."
        return 0
    fi

    # Smoke test: verify our exact flag combination works with a trivial prompt
    log_info "Running smoke test (this makes a small API call)..."

    local tmp_mcp
    tmp_mcp=$(mktemp -t angainor-install-mcp.XXXXXX)
    echo '{"mcpServers":{}}' > "$tmp_mcp"

    local smoke_output=""
    local smoke_exit=0

    if command -v timeout &> /dev/null; then
        smoke_output=$(echo "Reply with only the word OK" | timeout 30 claude \
            --dangerously-skip-permissions --print --no-session-persistence \
            --output-format text --strict-mcp-config --mcp-config "$tmp_mcp" \
            --disable-slash-commands 2>&1) || smoke_exit=$?
    else
        smoke_output=$(echo "Reply with only the word OK" | claude \
            --dangerously-skip-permissions --print --no-session-persistence \
            --output-format text --strict-mcp-config --mcp-config "$tmp_mcp" \
            --disable-slash-commands 2>&1) || smoke_exit=$?
    fi

    rm -f "$tmp_mcp"

    if [ $smoke_exit -eq 124 ]; then
        log_warn "Smoke test timed out after 30s. The CLI may be slow to start."
        log_warn "  Angainor should still work, but first iterations may be slow."
    elif [ $smoke_exit -ne 0 ]; then
        log_error "Smoke test failed (exit code: $smoke_exit)"
        # Show first 3 lines of output for debugging
        log_error "  Output: $(echo "$smoke_output" | head -3)"
        if echo "$smoke_output" | grep -qi "auth\|login\|api.key\|unauthorized\|forbidden"; then
            log_error "  This looks like an authentication issue."
            log_error "  Run 'claude' interactively first to complete login."
        elif echo "$smoke_output" | grep -qi "unknown option\|unrecognized"; then
            log_error "  Some CLI flags are not supported by this version."
            log_error "  Run 'claude update' to get the latest version."
        fi
    elif echo "$smoke_output" | grep -qi "ok"; then
        log_success "Smoke test passed — Claude CLI is ready for Angainor"
    else
        log_warn "Smoke test returned unexpected output: $(echo "$smoke_output" | head -1)"
        log_warn "  This may indicate authentication or API issues."
        log_warn "  Run 'claude' interactively to verify your setup."
    fi
}

# Download a file from the repo
download_file() {
    local remote_path="$1"
    local local_path="$2"

    local url="${REPO_URL}/${remote_path}"
    local dir
    dir=$(dirname "$local_path")

    mkdir -p "$dir"

    if command -v curl &> /dev/null; then
        curl -fsSL "$url" -o "$local_path"
    else
        wget -q "$url" -O "$local_path"
    fi
}

# Configure MCP for headless browser testing in containers
configure_mcp_playwright() {
    log_info "Configuring MCP for headless browser testing..."

    local mcp_config="$TARGET_DIR/.mcp.json"

    # Playwright server configuration for containerized environments
    # --no-sandbox: Required for Docker/containers without elevated privileges
    # --headless: Run browser without GUI for autonomous operation
    # --browser chromium: Use Chromium (most reliable in containers)
    local playwright_config
    playwright_config=$(cat << 'PLAYWRIGHT_JSON'
{
  "command": "npx",
  "args": [
    "@playwright/mcp@latest",
    "--browser", "chromium",
    "--headless",
    "--no-sandbox"
  ]
}
PLAYWRIGHT_JSON
)

    if [ -f "$mcp_config" ]; then
        # Merge with existing .mcp.json (add/update playwright server)
        local tmp_config
        tmp_config=$(mktemp)
        if jq --argjson pw "$playwright_config" '.mcpServers.playwright = $pw' "$mcp_config" > "$tmp_config" 2>/dev/null; then
            mv "$tmp_config" "$mcp_config"
            log_success "Updated .mcp.json with headless Playwright configuration"
        else
            log_warn "Could not parse existing .mcp.json, creating new one"
            rm -f "$tmp_config"
            # Fall through to create new file
            cat > "$mcp_config" << MCP_EOF
{
  "mcpServers": {
    "playwright": $playwright_config
  }
}
MCP_EOF
            log_success "Created .mcp.json with headless Playwright configuration"
        fi
    else
        # Create new .mcp.json
        cat > "$mcp_config" << MCP_EOF
{
  "mcpServers": {
    "playwright": $playwright_config
  }
}
MCP_EOF
        log_success "Created .mcp.json with headless Playwright configuration"
    fi
}

# Main installation
install_angainor() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         Angainor Installation Script             ║${NC}"
    echo -e "${GREEN}║   Autonomous AI Agent Loop for PRD Execution     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    # Resolve target directory to absolute path
    TARGET_DIR=$(cd "$TARGET_DIR" 2>/dev/null && pwd || echo "$TARGET_DIR")
    ANGAINOR_DIR="${TARGET_DIR}/.angainor"

    log_info "Installing Angainor to: $TARGET_DIR"

    check_dependencies
    validate_claude_cli

    # Create directory structure
    log_info "Creating directory structure..."
    mkdir -p "$ANGAINOR_DIR"
    mkdir -p "$ANGAINOR_DIR/skills/prd"
    mkdir -p "$ANGAINOR_DIR/skills/angainor"
    mkdir -p "$ANGAINOR_DIR/skills/read-transcript"
    mkdir -p "$ANGAINOR_DIR/skills/objective"
    mkdir -p "$ANGAINOR_DIR/scripts"

    # Download core files
    log_info "Downloading core files..."

    # Main script
    download_file "angainor.sh" "$ANGAINOR_DIR/angainor.sh"
    chmod +x "$ANGAINOR_DIR/angainor.sh"
    log_success "Downloaded angainor.sh"

    # Prompt templates
    download_file "prompt.md" "$ANGAINOR_DIR/prompt.md"
    log_success "Downloaded prompt.md"

    # Objective Mode prompt template
    download_file "objective-prompt.md" "$ANGAINOR_DIR/objective-prompt.md"
    log_success "Downloaded objective-prompt.md"

    # Skills - install to both local .angainor/skills/ and global ~/.claude/skills/
    log_info "Downloading skills..."
    local GLOBAL_SKILLS_DIR="$HOME/.claude/skills"
    mkdir -p "$GLOBAL_SKILLS_DIR/prd" "$GLOBAL_SKILLS_DIR/angainor" "$GLOBAL_SKILLS_DIR/read-transcript" "$GLOBAL_SKILLS_DIR/objective"

    # prd skill
    download_file "skills/prd/SKILL.md" "$ANGAINOR_DIR/skills/prd/SKILL.md"
    cp "$ANGAINOR_DIR/skills/prd/SKILL.md" "$GLOBAL_SKILLS_DIR/prd/SKILL.md"
    log_success "Installed skills/prd (local + global)"

    # angainor skill
    download_file "skills/angainor/SKILL.md" "$ANGAINOR_DIR/skills/angainor/SKILL.md"
    cp "$ANGAINOR_DIR/skills/angainor/SKILL.md" "$GLOBAL_SKILLS_DIR/angainor/SKILL.md"
    log_success "Installed skills/angainor (local + global)"

    # read-transcript skill
    download_file "skills/read-transcript/SKILL.md" "$ANGAINOR_DIR/skills/read-transcript/SKILL.md"
    cp "$ANGAINOR_DIR/skills/read-transcript/SKILL.md" "$GLOBAL_SKILLS_DIR/read-transcript/SKILL.md"
    log_success "Installed skills/read-transcript (local + global)"

    # objective skill (Objective Mode interactive planning)
    download_file "skills/objective/SKILL.md" "$ANGAINOR_DIR/skills/objective/SKILL.md"
    cp "$ANGAINOR_DIR/skills/objective/SKILL.md" "$GLOBAL_SKILLS_DIR/objective/SKILL.md"
    log_success "Installed skills/objective (local + global)"

    # Utility scripts
    log_info "Downloading utility scripts..."
    download_file "scripts/migrate-prd.sh" "$ANGAINOR_DIR/scripts/migrate-prd.sh"
    chmod +x "$ANGAINOR_DIR/scripts/migrate-prd.sh"
    log_success "Downloaded scripts/migrate-prd.sh"

    # Reference files
    log_info "Downloading reference files..."
    download_file "prd.json.example" "$ANGAINOR_DIR/prd.json.example"
    log_success "Downloaded prd.json.example"

    download_file "objective.json.example" "$ANGAINOR_DIR/objective.json.example"
    log_success "Downloaded objective.json.example"

    # Create wrapper script in target directory
    log_info "Creating wrapper script..."
    cat > "$TARGET_DIR/angainor.sh" << 'WRAPPER_EOF'
#!/usr/bin/env bash
#
# angainor.sh - Wrapper to run Angainor from the .angainor directory
#
# Usage: ./angainor.sh [OPTIONS] [max_iterations]
#
# Options:
#   --prd             Run in PRD mode (default)
#   --objective       Run in Objective mode
#   --verbose, -v     Enable verbose output for debugging
#   --debug           Enable debug logging to angainor-debug.log
#   --debug=FILE      Enable debug logging to specific file
#   --help, -h        Show help message
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANGAINOR_DIR="$SCRIPT_DIR/.angainor"

if [ ! -f "$ANGAINOR_DIR/angainor.sh" ]; then
    echo "Error: Angainor not installed. Run install-angainor.sh first."
    exit 1
fi

# Export project root so the main script uses correct paths
export ANGAINOR_PROJECT_ROOT="$SCRIPT_DIR"

exec "$ANGAINOR_DIR/angainor.sh" "$@"
WRAPPER_EOF
    chmod +x "$TARGET_DIR/angainor.sh"
    log_success "Created angainor.sh wrapper"

    # Patch angainor.sh to use ANGAINOR_PROJECT_ROOT if set
    log_info "Patching angainor.sh for project root support..."
    local main_script="$ANGAINOR_DIR/angainor.sh"
    local tmp_script
    tmp_script=$(mktemp)

    # Use awk to:
    # 1. Replace the first SCRIPT_DIR definition with conditional that respects ANGAINOR_PROJECT_ROOT
    # 2. Add ANGAINOR_LIB_DIR for library files (prompt.md, etc.)
    # 3. Update file references to use ANGAINOR_LIB_DIR
    # Note: SCRIPT_DIR is now defined early in the script (before argument parsing)
    awk '
    # Match the first SCRIPT_DIR= line (early definition for --debug default path)
    /^SCRIPT_DIR=.*\$\(cd.*dirname/ && !patched {
        print "# Use project root if set by wrapper, otherwise use script location"
        print "if [ -n \"${ANGAINOR_PROJECT_ROOT:-}\" ]; then"
        print "    SCRIPT_DIR=\"$ANGAINOR_PROJECT_ROOT\""
        print "    ANGAINOR_LIB_DIR=\"$SCRIPT_DIR/.angainor\""
        print "else"
        print "    SCRIPT_DIR=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\""
        print "    ANGAINOR_LIB_DIR=\"$SCRIPT_DIR\""
        print "fi"
        patched = 1
        next
    }
    # Update prompt.md references to use ANGAINOR_LIB_DIR
    /\$SCRIPT_DIR\/prompt\.md/ {
        gsub(/\$SCRIPT_DIR\/prompt\.md/, "$ANGAINOR_LIB_DIR/prompt.md")
    }
    /\$SCRIPT_DIR\/objective-prompt\.md/ {
        gsub(/\$SCRIPT_DIR\/objective-prompt\.md/, "$ANGAINOR_LIB_DIR/objective-prompt.md")
    }
    { print }
    ' "$main_script" > "$tmp_script" && mv "$tmp_script" "$main_script"
    chmod +x "$main_script"
    log_success "Patched angainor.sh"

    # Suggest .gitignore entries (don't modify automatically - user manages their own gitignore)
    # Note: prd.json, objective.json, progress.txt are intentionally NOT listed
    # because users may want to track these for cross-machine iteration continuity
    log_info "Suggested .gitignore entries (add manually if desired):"
    echo "    # Angainor temporary/generated files"
    echo "    .last-branch"
    echo "    transcripts/"
    echo "    screenshots/"
    echo "    metrics.json"
    echo "    angainor-debug.log"

    # Note: Skills are installed globally to ~/.claude/skills/ for Claude Code discovery
    log_success "Skills installed globally to ~/.claude/skills/"

    # Configure MCP for headless browser testing
    configure_mcp_playwright

    # Print success message
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         Angainor Installation Complete!          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Installed files:"
    echo "  $TARGET_DIR/angainor.sh                  - Main entry point"
    echo "  $TARGET_DIR/.mcp.json                    - MCP config for headless browser testing"
    echo "  $ANGAINOR_DIR/                           - Angainor internals"
    echo "  $ANGAINOR_DIR/prd.json.example           - PRD format reference"
    echo "  $ANGAINOR_DIR/objective.json.example     - Objective format reference"
    echo "  $ANGAINOR_DIR/objective-prompt.md        - Objective Mode agent instructions"
    echo "  ~/.claude/skills/{prd,angainor,read-transcript,objective}/ - Global skills"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Restart Claude Code to load new skills (exit and run 'claude' again)"
    echo "  2. Create prd.json in PROJECT ROOT (same dir as angainor.sh, NOT in .angainor/)"
    echo "     - Use /angainor skill to convert a markdown PRD, or"
    echo "     - Copy from $ANGAINOR_DIR/prd.json.example"
    echo "  3. Run: ./angainor.sh [max_iterations]"
    echo ""
    echo -e "${BLUE}Usage:${NC}"
    echo "  ./angainor.sh                    # PRD mode, 10 iterations"
    echo "  ./angainor.sh --objective 20     # Objective mode, 20 iterations"
    echo "  ./angainor.sh --verbose          # Verbose output for debugging"
    echo "  ./angainor.sh --debug            # Full debug logging"
    echo "  ./angainor.sh --timeout=3600     # Set iteration timeout (seconds)"
    echo "  ./angainor.sh --no-timeout       # Disable timeout for long benchmarks"
    echo "  ./angainor.sh --help             # Show all options"
    echo ""
    echo -e "${BLUE}Skills available:${NC}"
    echo "  /prd       - Generate a PRD from feature description"
    echo "  /angainor  - Convert markdown PRD to prd.json format"
    echo "  /objective - Define measurable objectives for Objective Mode"
    echo ""
    echo -e "${BLUE}Documentation:${NC}"
    echo "  See $ANGAINOR_DIR/prd.json.example for PRD format"
    echo "  See $ANGAINOR_DIR/objective.json.example for Objective Mode format"
    echo "  GitHub: https://github.com/thepriceisright/angainor"
    echo ""
}

# Run installation
install_angainor
