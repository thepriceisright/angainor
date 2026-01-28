# Next Iteration Priority Queue Design

## Problem Statement

The Angainor objective mode loop can get stuck when iterations discover important insights (e.g., "the VL model isn't working well, try a different one") but subsequent iterations don't follow through on those discoveries. The only mechanism for cross-iteration communication is unstructured text in progress.txt, which next iterations may or may not act upon.

## Solution

Add a **mandatory priority directive system** that allows an iteration to queue a specific action for the next iteration to address.

## Schema Changes

### New field in objective.json `status` object

```json
{
  "status": {
    "state": "running",
    "iterations": 7,
    "bestMetrics": {...},
    "metricHistory": [...],

    "nextIterationPriority": {
      "directive": "Try a different VL model for schedule extraction",
      "reason": "Qwen model on OpenRouter has 502/503 errors and extraction quality is poor",
      "approachCategory": "ALGORITHM_CHANGE",
      "suggestions": ["gpt-4v", "gemini-pro-vision"],
      "setByIteration": 7
    }
  }
}
```

### Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `directive` | string | Yes | What MUST be tried - specific and actionable |
| `reason` | string | Yes | Why this is important - context for next iteration |
| `approachCategory` | string | Yes | One of: PARAMETER_TUNING, ALGORITHM_CHANGE, DATA_PIPELINE, ARCHITECTURE, ERROR_ANALYSIS, ASSUMPTION_CHALLENGE |
| `suggestions` | array | No | Optional specific options to try |
| `setByIteration` | number | Yes | Which iteration set this priority |

### Lifecycle

1. **Set:** Iteration N writes `nextIterationPriority` before outputting `<iteration>COMPLETE</iteration>`
2. **Read:** Iteration N+1 sees it in the dynamic prompt header AND when reading objective.json
3. **Clear:** Iteration N+1 clears it after addressing (attempting or skipping with documented reason)

When null/absent: No priority set - iteration proceeds with normal Plateau-Breaking Protocol.

## Setting a Priority

### When to Set

An iteration should set a priority when it discovers something important that it cannot pursue in the current iteration (due to time, scope, or the one-experiment-per-iteration rule).

### Output Format

```xml
<set_priority>
  <directive>Try a different VL model for schedule extraction</directive>
  <reason>Qwen model on OpenRouter has 502/503 errors; Claude Sonnet works but may not be optimal for this task</reason>
  <approachCategory>ALGORITHM_CHANGE</approachCategory>
  <suggestions>["gpt-4v", "gemini-pro-vision", "claude-3-opus"]</suggestions>
</set_priority>
```

### Placement in Iteration Flow

1. Run experiment
2. Output `<metrics>` block
3. Append to progress.txt
4. **Output `<set_priority>` if applicable** (optional)
5. Output `<iteration>COMPLETE</iteration>`

### Rules

- Only ONE priority can be active at a time (new priority overwrites old)
- Cannot set priority for something you should have tried yourself (must justify why you didn't)
- Priority should be actionable and specific, not vague ("try something different")

## Handling a Priority

### Mandatory Response

When an iteration starts and `nextIterationPriority` exists, it MUST:

1. **Acknowledge immediately** - before any other analysis
2. **Decide action** - ATTEMPTING or SKIPPING
3. **Output response** - before forming hypothesis

### Output Format (Attempting)

```xml
<priority_response>
  <action>ATTEMPTING</action>
  <directive>Try a different VL model for schedule extraction</directive>
  <response>Will test GPT-4V via OpenRouter for schedule extraction, comparing against current Claude Sonnet baseline on projects 10083, 10022</response>
</priority_response>
```

### Output Format (Skipping)

```xml
<priority_response>
  <action>SKIPPING</action>
  <directive>Try a different VL model for schedule extraction</directive>
  <skip_reason>ALREADY_TRIED</skip_reason>
  <response>Iteration 9 already tested GPT-4V (see progress.txt). It performed worse than Claude Sonnet (F1=0.12 vs 0.33). No other VL models available on OpenRouter meet latency constraints.</response>
</priority_response>
```

### Valid Skip Reasons

| Reason | When to Use |
|--------|-------------|
| `CONSTRAINT_VIOLATION` | Would violate a constraint in objective.constraints |
| `ALREADY_TRIED` | This specific approach was already attempted (must cite iteration number) |
| `SUPERSEDED` | An intervening iteration solved the underlying problem differently |

### After Responding

- **If ATTEMPTING:** The priority directive becomes the hypothesis for this iteration
- **If SKIPPING:** Proceed with normal Plateau-Breaking Protocol

## Changes to angainor.sh

### 1. Parse `<set_priority>` from iteration output

After an iteration completes, extract the priority block and write to objective.json:

```bash
# Extract <set_priority> block from output
priority_block=$(echo "$OUTPUT" | grep -ozP '<set_priority>.*?</set_priority>' | tr '\0' '\n')

if [ -n "$priority_block" ]; then
  directive=$(echo "$priority_block" | grep -oP '(?<=<directive>).*(?=</directive>)')
  reason=$(echo "$priority_block" | grep -oP '(?<=<reason>).*(?=</reason>)')
  category=$(echo "$priority_block" | grep -oP '(?<=<approachCategory>).*(?=</approachCategory>)')
  suggestions=$(echo "$priority_block" | grep -oP '(?<=<suggestions>).*(?=</suggestions>)')

  # Write to objective.json
  jq --arg d "$directive" --arg r "$reason" --arg c "$category" --arg s "$suggestions" --argjson i "$iteration" \
    '.status.nextIterationPriority = {directive: $d, reason: $r, approachCategory: $c, suggestions: $s, setByIteration: $i}' \
    "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE"
fi
```

### 2. Include priority in dynamic prompt header

When generating the prompt for the next iteration:

```bash
if [ "$(jq -r '.status.nextIterationPriority // null' "$CONFIG_FILE")" != "null" ]; then
  PRIORITY_DIRECTIVE=$(jq -r '.status.nextIterationPriority.directive' "$CONFIG_FILE")
  PRIORITY_REASON=$(jq -r '.status.nextIterationPriority.reason' "$CONFIG_FILE")
  echo "⚠️ PRIORITY DIRECTIVE FROM ITERATION $PREV: $PRIORITY_DIRECTIVE"
  echo "   Reason: $PRIORITY_REASON"
  echo "   YOU MUST address this FIRST (attempt or document why skipping)"
fi
```

### 3. Clear priority after `<priority_response>`

```bash
# If iteration output contains <priority_response>, clear the priority
if echo "$OUTPUT" | grep -q '<priority_response>'; then
  jq '.status.nextIterationPriority = null' "$CONFIG_FILE" > tmp && mv tmp "$CONFIG_FILE"
fi
```

## Changes to objective-prompt.md

### Section A: Handling Incoming Priority

Add near the top, after "Your Task":

```markdown
## Priority Directive Handling (MANDATORY)

If `objective.json` contains `status.nextIterationPriority`, you MUST address it FIRST:

1. **Read the directive** from objective.json or the dynamic header
2. **Output `<priority_response>`** before any other analysis
3. **Either ATTEMPT or SKIP** (with documented reason)

**You may only SKIP if:**
- `CONSTRAINT_VIOLATION` - Would violate a constraint in objective.constraints
- `ALREADY_TRIED` - This specific approach was already attempted (cite iteration number)
- `SUPERSEDED` - An intervening iteration solved the underlying problem

**If ATTEMPTING:** The priority directive becomes your hypothesis for this iteration.
**If SKIPPING:** Proceed with normal Plateau-Breaking Protocol after documenting why.

Ignoring a priority directive is NOT allowed. You must explicitly respond to it.
```

### Section B: Setting Priority for Next Iteration

Add near the end, before "END EVERY ITERATION":

```markdown
## Setting Priority for Next Iteration (Optional)

If you discover something important that should be tried next but cannot pursue it yourself (one experiment per iteration), set a priority:

<set_priority>
  <directive>[Specific, actionable thing to try]</directive>
  <reason>[Why this is important - what evidence led to this]</reason>
  <approachCategory>[PARAMETER_TUNING|ALGORITHM_CHANGE|DATA_PIPELINE|ARCHITECTURE|ERROR_ANALYSIS|ASSUMPTION_CHALLENGE]</approachCategory>
  <suggestions>[Optional JSON array of specific options]</suggestions>
</set_priority>

**Rules:**
- Be specific and actionable (not "try something different")
- Include evidence/reasoning so next iteration understands context
- Only set if you genuinely believe this is the highest-value next step
```

## Example Flow

### Iteration 7 discovers model issues

```
## 2026-01-27 - Objective Iteration 7
...
**Pattern for future iterations:**
- Infrastructure note: Qwen model on OpenRouter unreliable; Claude works better
...
```

Iteration 7 outputs:
```xml
<set_priority>
  <directive>Try a different VL model for schedule extraction - test GPT-4V or Gemini Pro Vision</directive>
  <reason>Qwen model on OpenRouter has 502/503 errors. Claude Sonnet works but achieves only 33% accuracy. Different model architecture may perform better on table extraction.</reason>
  <approachCategory>ALGORITHM_CHANGE</approachCategory>
  <suggestions>["gpt-4v", "gemini-pro-vision", "claude-3-opus"]</suggestions>
</set_priority>

<iteration>COMPLETE</iteration>
```

### Iteration 8 receives priority

Dynamic prompt header shows:
```
⚠️ PRIORITY DIRECTIVE FROM ITERATION 7: Try a different VL model for schedule extraction - test GPT-4V or Gemini Pro Vision
   Reason: Qwen model on OpenRouter has 502/503 errors. Claude Sonnet works but achieves only 33% accuracy. Different model architecture may perform better on table extraction.
   YOU MUST address this FIRST (attempt or document why skipping)
```

Iteration 8 responds:
```xml
<priority_response>
  <action>ATTEMPTING</action>
  <directive>Try a different VL model for schedule extraction - test GPT-4V or Gemini Pro Vision</directive>
  <response>Will test GPT-4V via OpenRouter for schedule table extraction. Will run benchmark on projects 10083, 10022, 10076, 10055 comparing GPT-4V against Claude Sonnet baseline.</response>
</priority_response>
```

Then proceeds with GPT-4V experiment as the iteration's hypothesis.

## Success Criteria

1. When an iteration sets a priority, it appears in objective.json
2. The next iteration's dynamic prompt prominently displays the priority
3. The next iteration must output `<priority_response>` before proceeding
4. Priorities are cleared after being addressed
5. Skip reasons are documented and auditable
