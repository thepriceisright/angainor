# PRD: Angainor Objective Mode

## Introduction

Extend Angainor with a second execution mode for open-ended exploration where the approach is unknown upfront. Unlike PRD mode (predefined task list), Objective Mode iterates toward a measurable goal, discovering the solution path through experimentation.

**Use Cases:**
- "Make the image classifier 90% accurate"
- "Reduce API latency to under 100ms"
- "Achieve 95% test coverage"

**Design Document:** `docs/plans/2025-01-23-objective-mode-design.md`

## Goals

- Enable goal-driven autonomous iteration without predefined task lists
- Track quantitative metrics across iterations to measure progress
- Detect plateaus and impossible situations to avoid wasted iterations
- Provide an interactive `/objective` skill for defining measurable goals
- Maintain full backward compatibility with existing PRD mode

## User Stories

### Phase 1: Core Infrastructure

#### US-001: Add --objective and --prd flags to angainor.sh
**Description:** As a user, I want to specify the execution mode via command-line flags so that I can choose between PRD mode and Objective mode.

**Acceptance Criteria:**
- [ ] `./angainor.sh` defaults to PRD mode (existing behavior)
- [ ] `./angainor.sh --prd [max_iterations]` explicitly runs PRD mode
- [ ] `./angainor.sh --objective [max_iterations]` runs Objective mode
- [ ] Mode is displayed at startup: "Starting Angainor in PRD mode" or "Starting Angainor in OBJECTIVE mode"
- [ ] Error message if `objective.json` missing when using `--objective`
- [ ] Error message if `prd.json` missing when using `--prd` or default
- [ ] Existing PRD mode behavior unchanged (backward compatible)
- [ ] Typecheck passes (shellcheck on angainor.sh)

#### US-002: Create objective.json schema and example
**Description:** As a developer, I want a documented schema for objective.json so that the skill and script have a consistent format to work with.

**Acceptance Criteria:**
- [ ] Create `objective.json.example` in repo root with full schema
- [ ] Schema includes: `objective` (description, context, constraints)
- [ ] Schema includes: `verification` (command, successCriteria, metricsToTrack)
- [ ] Schema includes: `stopping` (maxIterations, plateauThreshold, maxConsecutiveFailures)
- [ ] Schema includes: `status` (state, iterations, bestMetrics, metricHistory)
- [ ] Example uses realistic values (not placeholder text)
- [ ] Typecheck passes

#### US-003: Create objective-prompt.md agent instructions
**Description:** As an autonomous agent, I need clear instructions for Objective mode so that I know how to iterate toward the goal.

**Acceptance Criteria:**
- [ ] Create `objective-prompt.md` in the angainor library directory (same location as `prompt.md`)
- [ ] Instructions explain: read objective.json, read progress.txt, form hypothesis, implement, verify
- [ ] Instructions include termination signal formats: `<objective>SUCCESS</objective>`, `<objective>IMPOSSIBLE</objective>`, `<objective>PLATEAU</objective>`
- [ ] Instructions include `<metrics>` output block format for metric extraction
- [ ] Instructions explain constraints must be respected
- [ ] Instructions include progress.txt format for objective mode iterations
- [ ] Typecheck passes

### Phase 2: Objective Mode Loop

#### US-004: Select config and prompt files based on mode
**Description:** As a script, I need to load the correct configuration and prompt files based on the execution mode.

**Acceptance Criteria:**
- [ ] PRD mode uses `prd.json` and `prompt.md`
- [ ] Objective mode uses `objective.json` and `objective-prompt.md`
- [ ] Config file path is resolved relative to script directory (where angainor.sh is invoked)
- [ ] Prompt file path is resolved from ANGAINOR_LIB_DIR
- [ ] Clear error if config file doesn't exist
- [ ] Typecheck passes (shellcheck)

#### US-005: Extract metrics from agent output
**Description:** As the loop controller, I need to parse metrics from the agent's output so that I can track progress over iterations.

**Acceptance Criteria:**
- [ ] Parse `<metrics>...</metrics>` XML block from agent output
- [ ] Support JSON format inside metrics block: `{"accuracy": 0.85, "loss": 0.42}`
- [ ] Support key=value format: `accuracy=0.85\nloss=0.42`
- [ ] Handle missing metrics block gracefully (warn, don't fail)
- [ ] Extracted metrics available as bash variables or JSON for further processing
- [ ] Typecheck passes (shellcheck)

#### US-006: Update objective.json with iteration metrics
**Description:** As the loop controller, I need to persist metrics to objective.json so that progress is tracked across iterations.

**Acceptance Criteria:**
- [ ] Increment `status.iterations` after each iteration
- [ ] Append current metrics to `status.metricHistory` array with iteration number
- [ ] Update `status.bestMetrics` if current metrics are better (compare primary metric from plateauThreshold.metric)
- [ ] Use jq for JSON manipulation (already a dependency)
- [ ] Handle first iteration (empty metricHistory) correctly
- [ ] Typecheck passes (shellcheck)

#### US-007: Implement SUCCESS termination check
**Description:** As the loop controller, I need to detect when the objective is achieved so that I can stop iterating.

**Acceptance Criteria:**
- [ ] Detect `<objective>SUCCESS</objective>` in agent output
- [ ] Update `status.state` to "success" in objective.json
- [ ] Print success message with final metrics
- [ ] Exit loop with success status (exit 0)
- [ ] Typecheck passes (shellcheck)

#### US-008: Implement IMPOSSIBLE termination check
**Description:** As the loop controller, I need to detect when the agent determines the objective is impossible so that I can stop and report why.

**Acceptance Criteria:**
- [ ] Detect `<objective>IMPOSSIBLE</objective>` in agent output
- [ ] Extract reason from `<reason>...</reason>` block
- [ ] Extract category from `<category>...</category>` block (technical|scope|resource)
- [ ] Update `status.state` to "impossible" in objective.json
- [ ] Store reason in `status.impossibleReason` field
- [ ] Print clear message explaining why objective is impossible
- [ ] Exit loop with distinct status (exit 2)
- [ ] Typecheck passes (shellcheck)

#### US-009: Implement PLATEAU termination check (agent-signaled)
**Description:** As the loop controller, I need to detect when the agent signals diminishing returns so that I can stop and summarize attempts.

**Acceptance Criteria:**
- [ ] Detect `<objective>PLATEAU</objective>` in agent output
- [ ] Extract attempts summary from `<attempts>...</attempts>` block
- [ ] Extract suggestion from `<suggestion>...</suggestion>` block
- [ ] Update `status.state` to "plateau" in objective.json
- [ ] Print plateau summary with attempts and suggestion
- [ ] Exit loop with distinct status (exit 3)
- [ ] Typecheck passes (shellcheck)

#### US-010: Implement metric-based plateau detection
**Description:** As the loop controller, I need to automatically detect plateaus from metrics even if the agent doesn't signal it.

**Acceptance Criteria:**
- [ ] Read plateau config: `stopping.plateauThreshold.{metric, minImprovement, windowSize}`
- [ ] Compare last N iterations (windowSize) of the tracked metric
- [ ] Detect plateau when improvement < minImprovement across the window
- [ ] Only trigger after at least windowSize iterations exist
- [ ] Update `status.state` to "plateau" when detected
- [ ] Print message: "Metric plateau detected (no improvement in last N iterations)"
- [ ] Typecheck passes (shellcheck)

#### US-011: Implement MAX_ITERATIONS termination
**Description:** As the loop controller, I need to respect the iteration budget and stop gracefully when exhausted.

**Acceptance Criteria:**
- [ ] Check iteration count against `stopping.maxIterations` from objective.json
- [ ] Also respect command-line max_iterations argument (use lower of the two)
- [ ] Detect `<objective>MAX_ITERATIONS</objective>` if agent outputs it
- [ ] Update `status.state` to "max_iterations" in objective.json
- [ ] Print summary with best metrics achieved
- [ ] Exit loop with distinct status (exit 4)
- [ ] Typecheck passes (shellcheck)

#### US-012: Print objective summary on completion
**Description:** As a user, I want a clear summary when the objective loop completes so that I understand what was achieved.

**Acceptance Criteria:**
- [ ] Print different summaries based on termination reason (SUCCESS, IMPOSSIBLE, PLATEAU, MAX_ITERATIONS)
- [ ] Include: iterations completed, best metrics, metric trend (improving/flat/declining)
- [ ] For SUCCESS: highlight which metrics met criteria
- [ ] For PLATEAU: show the window of stagnant iterations
- [ ] For IMPOSSIBLE: show the reason and category
- [ ] Typecheck passes (shellcheck)

### Phase 3: /objective Skill

#### US-013: Create /objective skill with clarifying questions
**Description:** As a user, I want an interactive skill that helps me define a measurable objective through guided questions.

**Acceptance Criteria:**
- [ ] Create `skills/objective/SKILL.md`
- [ ] Skill asks questions about: target endpoint/component, success metric, target value, constraints
- [ ] Questions use lettered multiple-choice format (A, B, C, D) where appropriate
- [ ] Questions adapt based on objective type (performance, accuracy, coverage, etc.)
- [ ] Skill can handle free-form answers for custom requirements
- [ ] Typecheck passes

#### US-014: Implement verification approach proposal
**Description:** As a user, I want the skill to propose how success will be measured so that I can approve or adjust the verification method.

**Acceptance Criteria:**
- [ ] Skill proposes verification command based on objective type
- [ ] Skill offers to create benchmark scripts if none exist
- [ ] Skill proposes metrics to track (relevant to objective type)
- [ ] Skill proposes success criteria expression (e.g., "accuracy >= 0.90")
- [ ] User can adjust any part of the proposal
- [ ] Typecheck passes

#### US-015: Implement stopping conditions proposal
**Description:** As a user, I want the skill to propose sensible stopping conditions so that the loop doesn't run forever or stop too early.

**Acceptance Criteria:**
- [ ] Propose default maxIterations based on objective complexity (10-20 typical)
- [ ] Propose plateauThreshold with sensible defaults (metric, minImprovement: 0.01, windowSize: 3)
- [ ] Propose maxConsecutiveFailures (default: 3)
- [ ] User can adjust all stopping parameters
- [ ] Explain what each parameter means in plain language
- [ ] Typecheck passes

#### US-016: Generate objective.json after approval
**Description:** As a user, I want the skill to create objective.json only after I approve the plan so that I have control over what gets executed.

**Acceptance Criteria:**
- [ ] Present complete plan summary before writing any files
- [ ] Wait for explicit user approval ("yes" or similar)
- [ ] Allow user to request adjustments before approval
- [ ] Write objective.json to project root after approval
- [ ] Initialize status fields: state="pending", iterations=0, bestMetrics={}, metricHistory=[]
- [ ] Print next steps: "To start: ./angainor.sh --objective"
- [ ] Typecheck passes

#### US-017: Support benchmark script creation
**Description:** As a user, I want the skill to create simple benchmark scripts when I don't have existing ones.

**Acceptance Criteria:**
- [ ] Offer to create benchmark when user selects "Create a benchmark for me"
- [ ] Generate Python script for common cases (API latency, test coverage, accuracy)
- [ ] Script outputs JSON with metrics matching metricsToTrack
- [ ] Script is executable and includes shebang
- [ ] Place script in `scripts/` directory with descriptive name
- [ ] Typecheck passes

### Phase 4: Installation & Documentation

#### US-018: Update install-angainor.sh for objective mode
**Description:** As a user installing Angainor, I want the installer to include all objective mode files.

**Acceptance Criteria:**
- [ ] Download `objective-prompt.md` to ANGAINOR_LIB_DIR
- [ ] Download `objective.json.example` to repo
- [ ] Download `skills/objective/SKILL.md`
- [ ] Existing installation behavior unchanged
- [ ] Typecheck passes (shellcheck)

#### US-019: Update CLAUDE.md with objective mode documentation
**Description:** As a developer, I want CLAUDE.md to document objective mode so that Claude instances understand both modes.

**Acceptance Criteria:**
- [ ] Add "Objective Mode" section explaining when to use it vs PRD mode
- [ ] Document objective.json schema fields
- [ ] Document termination conditions (SUCCESS, IMPOSSIBLE, PLATEAU, MAX_ITERATIONS)
- [ ] Document the /objective skill trigger phrases
- [ ] Add to skills table: `/objective` skill
- [ ] Typecheck passes

#### US-020: Update README.md with objective mode usage
**Description:** As a new user, I want README to explain objective mode so that I know how to use it.

**Acceptance Criteria:**
- [ ] Add "Objective Mode" section with use cases
- [ ] Include example invocation: `./angainor.sh --objective 15`
- [ ] Show example objective.json
- [ ] Explain the two-phase flow (interactive planning → autonomous execution)
- [ ] Typecheck passes

#### US-021: Update flowchart visualization for objective mode
**Description:** As a user, I want the flowchart to show the Objective Mode flow so that I can visualize how it works.

**Acceptance Criteria:**
- [ ] Add Objective Mode nodes and edges to the React Flow diagram
- [ ] Show the iteration loop: read objective → hypothesis → implement → verify → evaluate
- [ ] Show termination branches: SUCCESS, IMPOSSIBLE, PLATEAU, MAX_ITERATIONS
- [ ] Use distinct styling/colors to differentiate from PRD mode
- [ ] Flowchart remains readable with both modes shown
- [ ] `npm run build` succeeds
- [ ] `npm run lint` passes
- [ ] Verify in browser using dev-browser skill

### Phase 5: Backward Compatibility

#### US-022: Verify PRD mode still works unchanged
**Description:** As a user of existing PRD mode, I want to ensure the new changes don't break my workflow.

**Acceptance Criteria:**
- [ ] `./angainor.sh` (no flags) runs PRD mode as before
- [ ] `./angainor.sh 5` (number only) runs PRD mode with 5 iterations
- [ ] PRD mode still reads prd.json and prompt.md
- [ ] PRD mode still outputs `<promise>COMPLETE</promise>` on completion
- [ ] Verification blocks still work in PRD mode
- [ ] metrics.json output still works in PRD mode
- [ ] Typecheck passes (shellcheck)

## Functional Requirements

- FR-1: The system must support two execution modes: PRD mode and Objective mode
- FR-2: Mode selection via `--prd` or `--objective` flags; default is PRD mode
- FR-3: Objective mode must read from `objective.json` and use `objective-prompt.md`
- FR-4: Metrics must be extractable from agent output in JSON or key=value format
- FR-5: Metrics must be persisted to `objective.json` after each iteration
- FR-6: Loop must terminate on SUCCESS when `successCriteria` is met
- FR-7: Loop must terminate on IMPOSSIBLE when agent signals with reason
- FR-8: Loop must terminate on PLATEAU when agent signals or metrics stagnate
- FR-9: Loop must terminate on MAX_ITERATIONS when budget exhausted
- FR-10: The `/objective` skill must guide users through defining measurable goals
- FR-11: The skill must generate `objective.json` only after explicit user approval
- FR-12: All existing PRD mode functionality must remain unchanged

## Non-Goals

- No GUI or web interface for objective definition (CLI/conversation only)
- No automatic objective suggestion based on codebase analysis
- No multi-objective optimization (one objective at a time)
- No integration with external metric collection systems (Prometheus, etc.)
- No real-time metric streaming during iterations
- No hybrid mode combining objectives with predefined task lists (future consideration)

## Technical Considerations

- Use `jq` for JSON manipulation in bash (already a project dependency)
- Metric extraction should be robust to variations in agent output formatting
- Plateau detection algorithm should handle edge cases (not enough data, missing metrics)
- The skill should validate user inputs before generating objective.json
- Exit codes should be distinct for different termination reasons (0=success, 1=error, 2=impossible, 3=plateau, 4=max_iterations)

## Success Metrics

- User can define an objective via `/objective` skill in under 5 minutes
- Objective mode correctly tracks metrics across 10+ iterations
- Plateau detection triggers within 1 iteration of actual stagnation
- PRD mode passes all existing behavioral tests
- Documentation enables new users to understand and use objective mode without external help

## Open Questions

1. ~~Metric output format~~ → **Decided:** Support both JSON and key=value parsing
2. ~~Benchmark creation~~ → **Decided:** Skill can create benchmarks
3. **Hybrid mode:** Should there be a way to combine objective + task list? → Deferred to future PRD
4. **Metric visualization:** Add ASCII chart of metric history in summary? → Nice to have, not required for MVP
