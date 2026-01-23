# PRD: OpenCode Support for Angainor

## Introduction

Add OpenCode (https://opencode.ai) as an alternative AI coding tool for Angainor loop execution. Currently, Angainor only supports Claude Code. This feature enables users to choose between Claude Code and OpenCode via a command-line flag, with full feature parity including retry logic, timeout handling, and autonomous permissions.

## Goals

- Enable OpenCode as an alternative to Claude Code for loop execution
- Provide command-line flag to select AI tool (`--opencode` or `--claude`)
- Achieve feature parity: retry logic, timeout handling, transcript capture
- Support per-tool configuration sections for tool-specific settings
- Provide easy API key and model configuration for OpenCode
- Maintain backward compatibility (Claude Code remains default)

## User Stories

### US-001: Add --opencode and --claude CLI flags
**Description:** As a user, I want to specify which AI tool to use via command-line flags so that I can choose between Claude Code and OpenCode.

**Acceptance Criteria:**
- [ ] `./angainor.sh --opencode` runs iterations using OpenCode
- [ ] `./angainor.sh --claude` explicitly runs using Claude Code
- [ ] Default behavior (no flag) uses Claude Code for backward compatibility
- [ ] Flags work in combination with existing flags (`--prd`, `--objective`, `max_iterations`)
- [ ] Help text updated to document new flags
- [ ] Typecheck passes (shellcheck on bash script)

### US-002: Create OpenCode invocation function
**Description:** As the system, I need to invoke OpenCode with the correct command and flags so that prompts execute in non-interactive autonomous mode.

**Acceptance Criteria:**
- [ ] Function `run_opencode()` executes `opencode run` with prompt content
- [ ] Non-interactive mode confirmed (no user prompts during execution)
- [ ] Output captured to transcript file
- [ ] Exit code captured for retry logic
- [ ] Timeout protection applied (same as Claude Code: 10 minutes default)
- [ ] Typecheck passes (shellcheck)

### US-003: Configure OpenCode autonomous permissions
**Description:** As a user, I want OpenCode to run without permission prompts so that the autonomous loop can execute unattended.

**Acceptance Criteria:**
- [ ] Document required OpenCode permission config: `"permission": "allow"`
- [ ] Check for valid OpenCode config before starting loop
- [ ] Provide clear error message if permissions not configured
- [ ] Add example `opencode.json` config to repository
- [ ] Typecheck passes (shellcheck)

### US-004: Add OpenCode API key and model setup helper
**Description:** As a user, I want an easy way to configure my API key and model selection for OpenCode so that I can get started quickly.

**Acceptance Criteria:**
- [ ] Create `scripts/setup-opencode.sh` helper script
- [ ] Script checks if OpenCode is installed, provides install instructions if not
- [ ] Script guides user through API provider selection (Anthropic, OpenAI, etc.)
- [ ] Script creates/updates `opencode.json` with model configuration
- [ ] Script validates API key works before saving
- [ ] README updated with setup instructions
- [ ] Typecheck passes (shellcheck)

### US-005: Implement retry logic for OpenCode
**Description:** As the system, I need to retry OpenCode invocations on transient errors so that temporary API issues don't halt the loop.

**Acceptance Criteria:**
- [ ] Detect transient errors in OpenCode output (rate limits, timeouts, connection errors)
- [ ] Retry up to 3 times with exponential backoff (same as Claude Code)
- [ ] Log retry attempts to console
- [ ] Record failure in metrics if all retries exhausted
- [ ] Typecheck passes (shellcheck)

### US-006: Refactor tool invocation to use abstraction
**Description:** As a developer, I want tool invocation abstracted so that adding future AI tools is straightforward.

**Acceptance Criteria:**
- [ ] Create `run_ai_tool()` function that dispatches to appropriate tool
- [ ] Both `run_claude()` and `run_opencode()` use consistent interface
- [ ] Interface: `run_ai_tool <prompt_file> <transcript_file>` returns output and exit code
- [ ] Tool selection based on `$AI_TOOL` variable set from CLI flag
- [ ] Existing behavior unchanged when using Claude Code
- [ ] Typecheck passes (shellcheck)

### US-007: Add per-tool configuration section to prd.json/objective.json
**Description:** As a user, I want to specify tool-specific configuration in my project config so that different projects can use different tools and settings.

**Acceptance Criteria:**
- [ ] Add optional `toolConfig` section to prd.json schema
- [ ] Support `toolConfig.opencode.model` for model override
- [ ] Support `toolConfig.opencode.timeout` for custom timeout
- [ ] Support `toolConfig.claude.timeout` for Claude-specific timeout
- [ ] CLI flag overrides config file settings
- [ ] Update prd.json.example and objective.json.example with examples
- [ ] Typecheck passes (shellcheck)

### US-008: Update documentation for OpenCode support
**Description:** As a user, I want clear documentation so that I understand how to use OpenCode with Angainor.

**Acceptance Criteria:**
- [ ] README.md updated with OpenCode usage section
- [ ] CLAUDE.md updated with OpenCode configuration details
- [ ] Add "Choosing an AI Tool" section comparing Claude Code vs OpenCode
- [ ] Document environment requirements for each tool
- [ ] Document troubleshooting for common OpenCode issues
- [ ] Typecheck passes (markdownlint or manual review)

### US-009: Validate OpenCode installation before loop start
**Description:** As the system, I need to verify OpenCode is installed and configured before starting the loop so that users get clear error messages.

**Acceptance Criteria:**
- [ ] Check `opencode` command exists in PATH when `--opencode` flag used
- [ ] Check `opencode.json` exists with required permission config
- [ ] Check API credentials are configured (auth.json exists or env var set)
- [ ] Provide actionable error messages for each missing requirement
- [ ] Suggest running `scripts/setup-opencode.sh` if not configured
- [ ] Typecheck passes (shellcheck)

### US-010: Handle OpenCode-specific output format
**Description:** As the system, I need to parse OpenCode output correctly so that verification and completion signals work properly.

**Acceptance Criteria:**
- [ ] Test that `<promise>COMPLETE</promise>` signal works with OpenCode output
- [ ] Test that `<verification>` blocks are detected in OpenCode output
- [ ] Test that checkmark verification (✅/❌) works with OpenCode output
- [ ] Test that `<metrics>` blocks are extracted from OpenCode output
- [ ] Verify story ID extraction works with OpenCode output format
- [ ] Typecheck passes (shellcheck)

## Functional Requirements

- FR-1: The system must support `--opencode` flag to use OpenCode for loop execution
- FR-2: The system must support `--claude` flag to explicitly use Claude Code
- FR-3: The system must default to Claude Code when no tool flag is specified
- FR-4: The system must invoke OpenCode using `opencode run "<prompt>"` for non-interactive execution
- FR-5: The system must require OpenCode permission config set to `"permission": "allow"` for autonomous operation
- FR-6: The system must apply the same retry logic (3 attempts, exponential backoff) to OpenCode as Claude Code
- FR-7: The system must apply timeout protection (default 10 minutes) to OpenCode invocations
- FR-8: The system must capture OpenCode output to transcript files in the same format as Claude Code
- FR-9: The system must validate OpenCode installation and configuration before starting the loop
- FR-10: The system must provide a setup helper script for OpenCode API key and model configuration

## Non-Goals

- No automatic installation of OpenCode (user must install separately)
- No support for other AI tools beyond Claude Code and OpenCode in this iteration
- No GUI or interactive configuration wizard
- No synchronization of settings between Claude Code and OpenCode
- No performance comparison or benchmarking between tools
- No tool-specific prompt modifications (same prompt.md used for both)

## Technical Considerations

### OpenCode CLI Differences
- Claude Code: `claude --dangerously-skip-permissions --print < prompt.md`
- OpenCode: `opencode run "$(cat prompt.md)"` with `opencode.json` containing `"permission": "allow"`

### Configuration Files
- Claude Code: Uses `~/.claude/` and project-level `.claude/`
- OpenCode: Uses `opencode.json` in project root and `~/.local/share/opencode/auth.json` for credentials

### Output Format
- Both tools output to stdout
- OpenCode with `--format json` outputs structured JSON (may be useful for future features)
- Standard output mode should work with existing verification parsing

### Environment Variables
- OpenCode: `OPENCODE_PERMISSION='{"*":"allow"}'` can override permission config
- This provides a way to run autonomously without modifying project files

## Success Metrics

- Users can run full PRD execution using OpenCode without manual intervention
- Retry logic handles transient OpenCode API errors gracefully
- Setup script enables new users to configure OpenCode in under 2 minutes
- No regression in Claude Code functionality
- Documentation enables self-service troubleshooting

## Open Questions

1. Should we support `ANGAINOR_DEFAULT_TOOL` environment variable for user preference without CLI flag?
2. Should OpenCode output use `--format json` for more reliable parsing, or stick with standard output for consistency?
3. Should the setup script support multiple API providers or focus on Anthropic (most common)?
