# LLM-Based Output Extraction Design

## Problem Statement

The objective mode agent sometimes outputs results in natural language instead of the required XML format. This causes:
1. Metrics not being captured (`<metrics>` block missing)
2. Priority directives not being set (`<set_priority>` block missing)
3. Iteration completion not being detected (`<iteration>COMPLETE</iteration>` missing)

## Solution: LLM Post-Processing

Add a small, fast LLM call to extract structured data from the agent's raw output, regardless of format.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Current Flow                                                 │
│ Agent Output → Regex/Grep Parsing → objective.json update   │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ New Flow                                                     │
│ Agent Output → LLM Extraction → Structured JSON → Update    │
└─────────────────────────────────────────────────────────────┘
```

## Extraction Prompt Design

### System Prompt

```
You are a structured data extractor. Given raw output from an AI agent iteration, extract the following information into JSON format. Be precise and extract only what is explicitly stated.
```

### User Prompt Template

```
Extract the following from this agent iteration output:

1. **metrics**: Any numerical measurements mentioned (accuracy, precision, recall, F1, etc.)
2. **iteration_complete**: Did the agent signal completion? (true/false)
3. **termination_signal**: If ending, what signal? (SUCCESS/IMPOSSIBLE/PLATEAU/null)
4. **priority_directive**: Any suggestion for what the next iteration should try
5. **approach_category**: What category of approach was used?

Output ONLY valid JSON in this exact format:
{
  "metrics": {
    "fixture_type_accuracy": 0.33,
    "precision": 0.40,
    ...
  },
  "iteration_complete": true,
  "termination_signal": null,
  "priority_directive": {
    "directive": "string or null",
    "reason": "string or null",
    "approach_category": "PARAMETER_TUNING|ALGORITHM_CHANGE|DATA_PIPELINE|ARCHITECTURE|ERROR_ANALYSIS|ASSUMPTION_CHALLENGE|null",
    "suggestions": ["array", "of", "suggestions"]
  }
}

If a field cannot be determined from the output, use null.

---
AGENT OUTPUT:
{output}
---
```

## Example Extraction

### Input (from test_transcript.txt)

```
Iteration 15 Results (actual 16):
- fixture_type_accuracy: 0.0454 (REGRESSION from 0.3333)
- Constraint status: All satisfied
- Changes made:
  a. Updated VL LLM extraction prompt to emphasize EMB variants and EXIT types
  b. Attempted index pre-filtering (reverted - caused empty index)

Root Cause Analysis:
- VL LLM schedule extraction is fundamentally unreliable across models (Gemini, Claude both fail)
- Legend extraction finds garbage (dates, addresses) instead of fixture symbols

Pattern for future iterations:
- FAILED: Prompt engineering for VL LLM extraction (multiple iterations tried)
- FAILED: Model switching (Claude Sonnet, Gemini Flash, now prompt changes)
- Consider: Complete architecture change - use VL LLM to directly count fixtures on floor plans
```

### Expected Output

```json
{
  "metrics": {
    "fixture_type_accuracy": 0.0454
  },
  "iteration_complete": true,
  "termination_signal": null,
  "priority_directive": {
    "directive": "Use VL LLM to directly count fixtures on floor plans instead of legend-based matching",
    "reason": "VL LLM schedule extraction is fundamentally unreliable across models. Legend extraction finds garbage instead of fixture symbols. Multiple approaches have failed.",
    "approach_category": "ARCHITECTURE",
    "suggestions": ["direct VL counting", "skip legend matching"]
  }
}
```

## Implementation Options

### Option A: Claude API Direct Call (Recommended)

Use Anthropic API with claude-3-haiku for fast, cheap extraction:

```bash
# In angainor.sh, after capturing OUTPUT
extract_with_llm() {
  local output="$1"
  local extraction_prompt="$(cat <<EOF
Extract structured data from this agent output...
$output
EOF
)"

  # Call Claude API via curl
  curl -s https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "{
      \"model\": \"claude-3-haiku-20240307\",
      \"max_tokens\": 1024,
      \"messages\": [{\"role\": \"user\", \"content\": \"$extraction_prompt\"}]
    }" | jq -r '.content[0].text'
}
```

**Pros:**
- Fast (~1-2 seconds)
- Cheap (~$0.001 per extraction)
- Reliable JSON output with Haiku
- No additional dependencies

**Cons:**
- Requires ANTHROPIC_API_KEY
- Additional API call per iteration

### Option B: OpenRouter (Alternative)

Use OpenRouter for model flexibility:

```bash
curl -s https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"anthropic/claude-3-haiku\",
    \"messages\": [{\"role\": \"user\", \"content\": \"$extraction_prompt\"}]
  }"
```

### Option C: Local LLM (No API needed)

Use a local model like Ollama for offline extraction:

```bash
ollama run llama3.2:3b "$extraction_prompt"
```

**Pros:**
- No API costs
- Works offline
- Privacy

**Cons:**
- Requires local model setup
- Slower
- Less reliable JSON output

## Integration into angainor.sh

### New Function: `extract_iteration_data()`

```bash
# Extract structured data from agent output using LLM
# Arguments: raw_output
# Returns: JSON with metrics, priority, completion status
extract_iteration_data() {
  local output="$1"

  # First try: regex/grep for XML tags (fast path)
  if echo "$output" | grep -q "<metrics>"; then
    # Use existing extraction logic
    return
  fi

  # Fallback: LLM extraction for natural language output
  log_verbose "No XML tags found, using LLM extraction..."

  local extraction_prompt=$(cat <<'PROMPT'
Extract from this agent output:
1. metrics (numerical measurements)
2. iteration_complete (true/false)
3. priority_directive (what to try next)

Output ONLY valid JSON:
{"metrics":{...},"iteration_complete":bool,"priority_directive":{...}}
PROMPT
)

  # Combine prompt with output (escape for JSON)
  local full_prompt="$extraction_prompt\n\nAGENT OUTPUT:\n$output"

  # Call Haiku for extraction
  local result=$(curl -s https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$(jq -n --arg p "$full_prompt" '{
      model: "claude-3-haiku-20240307",
      max_tokens: 1024,
      messages: [{role: "user", content: $p}]
    }')" | jq -r '.content[0].text')

  echo "$result"
}
```

### Integration Point

After line ~2240 in angainor.sh:

```bash
# Current: Try to extract metrics from XML
EXTRACTED_METRICS=$(extract_metrics "$OUTPUT_TAIL")

# NEW: If XML extraction failed, try LLM extraction
if [ -z "$EXTRACTED_METRICS" ] || [ "$EXTRACTED_METRICS" = "{}" ]; then
  echo "  ⚠ No XML metrics found, trying LLM extraction..."
  LLM_EXTRACTED=$(extract_iteration_data "$OUTPUT_TAIL")

  if [ -n "$LLM_EXTRACTED" ]; then
    EXTRACTED_METRICS=$(echo "$LLM_EXTRACTED" | jq -c '.metrics // {}')

    # Also extract priority directive if present
    PRIORITY=$(echo "$LLM_EXTRACTED" | jq -c '.priority_directive // null')
    if [ "$PRIORITY" != "null" ]; then
      echo "  ✓ LLM extracted priority directive"
      # Write to objective.json
      jq --argjson p "$PRIORITY" --argjson i "$i" \
        '.status.nextIterationPriority = ($p + {setByIteration: $i})' \
        "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
  fi
fi
```

## Cost Analysis

| Model | Cost per 1K input tokens | Cost per 1K output tokens | Est. cost per extraction |
|-------|--------------------------|---------------------------|-------------------------|
| Claude 3 Haiku | $0.00025 | $0.00125 | ~$0.001 |
| Claude 3.5 Sonnet | $0.003 | $0.015 | ~$0.01 |
| GPT-4o-mini | $0.00015 | $0.0006 | ~$0.0005 |

For a 100-iteration objective run: ~$0.10 - $1.00 total extraction cost.

## Fallback Chain

1. **Try XML parsing first** (free, instant)
2. **If XML fails, try LLM extraction** (cheap, ~2 seconds)
3. **If LLM fails, try progress.txt parsing** (existing fallback)
4. **If all fail, log warning and continue** (no metrics recorded)

## Success Criteria

1. Metrics are extracted from ≥95% of iterations (up from ~50% with XML-only)
2. Priority directives are captured when agent suggests next steps
3. Extraction adds <5 seconds to iteration processing
4. Total cost <$0.01 per extraction

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| LLM hallucinating metrics | Compare against progress.txt; require numbers to appear in source |
| API rate limits | Cache extraction prompts; batch if needed |
| API unavailable | Fall back to progress.txt parsing |
| Increased iteration time | Use Haiku (fast); parallelize with other processing |
| JSON parsing errors | Validate with jq; retry once on failure |

## Next Steps

1. Implement `extract_iteration_data()` function in angainor.sh
2. Add API key handling (use existing ANTHROPIC_API_KEY or OPENROUTER_API_KEY)
3. Test with sample outputs from test_transcript.txt
4. Add --no-llm-extraction flag for users who don't want API calls
5. Document in CLAUDE.md
