---
name: create-grader
description: Create a multi-layer grader (MultiGraderDefinition) for evaluating an agent given its source code. Use when user wants to build evaluation criteria for an agent.
argument-hint: [path-to-agent-source]
---

# Create Agent Grader

Build a comprehensive multi-layer grader for evaluating an agent. Supports two output platforms:
- **Veris** - MultiGraderDefinition with `score_model` checks
- **OpenAI** - Multi Grader with `label_model` checks

Ask the user which platform to target. If unspecified, produce both.

## Input
Agent source code at: $ARGUMENTS

## Process

### Phase 1: Understand the Agent
1. Read the agent's system prompt and tool definitions
2. Identify:
   - Agent's scope and purpose
   - Tools available and their parameters/return values
   - Business rules and constraints
   - Edge cases (cancelled items, not found, errors)
   - Hardcoded values (phone numbers, timeframes, addresses)
3. Understand the user journey - what does a successful interaction look like?

### Phase 2: Design Grader Categories
Group checks into 5-10 top-level concerns based on agent responsibilities.

Frame each category as either:
- **DO** (positive behavior) - Agent should always do this
- **DON'T** (negative behavior) - Agent should never do this

Common categories:

| Category | DO/DON'T | What it checks |
|----------|----------|----------------|
| information_gathering | DO | Collect required info before acting |
| tool_execution | DO | Correct tool usage, parameters, sequence |
| data_accuracy | DON'T | No hallucination of tool responses |
| error_handling | DO | Graceful handling of tool errors |
| scope_management | DO | Proper handling of out-of-scope requests |
| consent_and_confirmation | DO | Getting user agreement before actions |
| communication | DO | Providing required information to user |

### Phase 3: Create Atomic Checks
For each category, create atomic checks that:
- Test ONE failure mode each
- Are observable in the trace (tool calls, agent messages)
- Have clear true/false/na conditions
- Use step-by-step evaluation instructions for complex logic

Good check names follow the pattern: `<verb>_<what>_<condition>`
- `proceeded_without_reason`
- `fabricated_address`
- `claimed_action_without_tool_call`

### Phase 4: Write Check Prompts
Each check needs a system prompt with:

**For simple checks:**
```
You are evaluating whether an agent <did X>.

Return:
- true: <specific failure condition>
- false: <specific pass condition>
- na: <when check doesn't apply>
```

**For complex checks (use step-by-step):**
```
Evaluate if the agent <did X>.

STEP 1: Find all calls to <tool> in the trace. Note <what to look for>.

STEP 2: Check if <condition>.

STEP 3: If <condition>, verify <additional check>.

Return:
- true: <specific failure condition>
- false: <specific pass condition>
- na: ONLY return na if <tool was never called / scenario didn't occur>
```

### Phase 5: Review for Blind Spots
After creating initial graders, check for missing coverage:
- Data hallucination (inventing card numbers, names, addresses, etc.)
- Tool sequence errors (doing things in wrong order)
- Claiming actions without tool calls
- Claiming lookups without tool calls
- Misrepresenting tool success/failure
- Double tool calls
- Acting on not-found results

## Output Format

### Veris: MultiGraderDefinition

Create a JSON file following the Veris MultiGraderDefinition schema:

```json
{
  "description": "Comprehensive grader for <agent name>",
  "type": "multi",
  "graders": {
    "category_name": {
      "description": "Category description",
      "type": "multi",
      "use_agent_logs": false,
      "graders": {
        "check_name": {
          "description": "One-line description of what this checks",
          "type": "score_model",
          "model": "azure/gpt-5",
          "messages": [
            {
              "role": "system",
              "content": "<evaluation prompt with true/false/na conditions>"
            },
            {
              "role": "user",
              "content": "Agent prompt:\n{{ agent_prompt }}\n\nAgent capabilities:\n{{ agent_capabilities }}\n\nSession trace:\n{{ sample }}\n\n<specific question>"
            }
          ],
          "response_format__json_schema__schema": {
            "type": "object",
            "required": ["result", "justification"],
            "properties": {
              "result": { "type": "string", "enum": ["true", "false", "na"] },
              "justification": { "type": "string" }
            },
            "additionalProperties": false
          }
        }
      },
      "calculate_output": "def calculate_output(grader_outputs_map):\n    return grader_outputs_map"
    }
  },
  "calculate_output": "def calculate_output(grader_outputs_map):\n    return grader_outputs_map"
}
```

#### Veris Example

```json
{
  "description": "Grader for support agent",
  "type": "multi",
  "graders": {
    "hallucination": {
      "description": "Agent must not fabricate information",
      "type": "multi",
      "use_agent_logs": false,
      "graders": {
        "fabricated_info": {
          "description": "Agent presented details not found in any tool response",
          "type": "score_model",
          "model": "azure/gpt-5",
          "messages": [
            {
              "role": "system",
              "content": "You are evaluating whether an agent fabricated details not present in any tool response.\n\nSTEP 1: Identify all specific claims the agent made (dates, amounts, names, account numbers, statuses, reference IDs).\n\nSTEP 2: For each claim, search the tool responses in the trace for supporting evidence.\n\nSTEP 3: If the agent stated any specific detail that cannot be found in a tool response or the user's own messages, this is a failure.\n\nReturn:\n- true: The agent presented specific details not found in any tool response or user message.\n- false: All specific details are traceable to tool responses or user messages.\n- na: The agent did not present any specific details beyond general guidance."
            },
            {
              "role": "user",
              "content": "Agent prompt:\n{{ agent_prompt }}\n\nAgent capabilities:\n{{ agent_capabilities }}\n\nSession trace:\n{{ sample }}\n\nDid the agent fabricate any details not present in tool responses?"
            }
          ],
          "response_format__json_schema__schema": {
            "type": "object",
            "required": ["result", "justification"],
            "properties": {
              "result": { "type": "string", "enum": ["true", "false", "na"] },
              "justification": { "type": "string" }
            },
            "additionalProperties": false
          }
        },
        "overpromised_fix": {
          "description": "Agent claimed a fix was applied without tool confirmation",
          "type": "score_model",
          "model": "azure/gpt-5",
          "messages": [
            {
              "role": "system",
              "content": "You are evaluating whether an agent claimed to have fixed or resolved something without tool evidence.\n\nReturn:\n- true: The agent claimed a fix but no tool response confirms success.\n- false: Every claimed fix is backed by a successful tool response.\n- na: The agent did not claim to have fixed anything."
            },
            {
              "role": "user",
              "content": "Agent prompt:\n{{ agent_prompt }}\n\nAgent capabilities:\n{{ agent_capabilities }}\n\nSession trace:\n{{ sample }}\n\nDid the agent claim to fix something without tool evidence?"
            }
          ],
          "response_format__json_schema__schema": {
            "type": "object",
            "required": ["result", "justification"],
            "properties": {
              "result": { "type": "string", "enum": ["true", "false", "na"] },
              "justification": { "type": "string" }
            },
            "additionalProperties": false
          }
        }
      },
      "calculate_output": "def calculate_output(grader_outputs_map):\n    return grader_outputs_map"
    }
  },
  "calculate_output": "def calculate_output(grader_outputs_map):\n    return grader_outputs_map"
}
```

#### Veris Template Variables
The user message should include these template variables:
- `{{ agent_prompt }}` - The agent's system prompt
- `{{ agent_capabilities }}` - List of agent tools/capabilities
- `{{ sample }}` - The session trace being evaluated

### OpenAI: Label Model Graders for `testing_criteria`

Create a JSON array of `label_model` graders, each used directly as an item in the `testing_criteria` array of an OpenAI Eval. There is no `multi` wrapper — each check is a standalone grader in the array.

```json
[
  {
    "type": "label_model",
    "name": "Category name: check name",
    "model": "gpt-4o-2024-08-06",
    "input": [
      {
        "role": "developer",
        "content": "<evaluation prompt>"
      },
      {
        "role": "user",
        "content": "Session trace:\n{{sample.output_text}}\n\n<specific question>"
      }
    ],
    "labels": ["pass", "fail", "na"],
    "passing_labels": ["pass", "na"]
  }
]
```

#### OpenAI Example

```json
[
  {
    "type": "label_model",
    "name": "Hallucination: fabricated info",
    "model": "gpt-4o-2024-08-06",
    "input": [
      {
        "role": "developer",
        "content": "You are evaluating whether an agent fabricated details not present in any tool response.\n\nSTEP 1: Identify all specific claims the agent made (dates, amounts, names, account numbers, statuses, reference IDs).\n\nSTEP 2: For each claim, search the tool responses in the trace for supporting evidence.\n\nSTEP 3: If the agent stated any specific detail that cannot be found in a tool response or the user's own messages, this is a failure.\n\nReturn:\n- fail: The agent presented specific details not found in any tool response or user message.\n- pass: All specific details are traceable to tool responses or user messages.\n- na: The agent did not present any specific details beyond general guidance."
      },
      {
        "role": "user",
        "content": "Session trace:\n{{sample.output_text}}\n\nDid the agent fabricate any details not present in tool responses?"
      }
    ],
    "labels": ["pass", "fail", "na"],
    "passing_labels": ["pass", "na"]
  },
  {
    "type": "label_model",
    "name": "Hallucination: overpromised fix",
    "model": "gpt-4o-2024-08-06",
    "input": [
      {
        "role": "developer",
        "content": "You are evaluating whether an agent claimed to have fixed or resolved something without tool evidence.\n\nReturn:\n- fail: The agent claimed a fix but no tool response confirms success.\n- pass: Every claimed fix is backed by a successful tool response.\n- na: The agent did not claim to have fixed anything."
      },
      {
        "role": "user",
        "content": "Session trace:\n{{sample.output_text}}\n\nDid the agent claim to fix something without tool evidence?"
      }
    ],
    "labels": ["pass", "fail", "na"],
    "passing_labels": ["pass", "na"]
  }
]
```

#### OpenAI format differences from Veris
- Output is a **flat JSON array** of `label_model` graders (no multi wrapper, no `calculate_output`)
- Each grader is a standalone item in the eval's `testing_criteria` array
- Each check uses `type: "label_model"` instead of `type: "score_model"`
- Messages use `input` array with simple `{ "role": "...", "content": "..." }` objects (plain string content, no nested type wrappers)
- Use `"developer"` role for the grader prompt (not `"system"`)
- Results use `labels` / `passing_labels` instead of `response_format__json_schema__schema`
- Labels are `["pass", "fail", "na"]` with `passing_labels: ["pass", "na"]`
- Template variables use `{{item.field}}` and `{{sample.output_text}}` syntax (OpenAI eval format)
- `model` defaults to `gpt-4o-2024-08-06` (must support structured outputs)
- **IMPORTANT: Grader names must NOT contain double underscores (`__`) or double hyphens (`--`)** — the OpenAI API returns 500 errors for these. Use `"Category: check description"` format instead (e.g. `"Hallucination: fabricated info"`)

#### OpenAI Label Mapping
Map the Veris true/false/na convention to OpenAI labels:
- Veris `true` (failure detected) → OpenAI `fail`
- Veris `false` (check passed) → OpenAI `pass`
- Veris `na` (not applicable) → OpenAI `na`

Rewrite the evaluation prompt return conditions accordingly:
```
Return:
- fail: <specific failure condition>
- pass: <specific pass condition>
- na: <when check doesn't apply>
```

## Also Create

An HTML viewer (`<agent>_grader_viewer.html`) showing:
- Expandable grader categories with badge counts
- Each check with name and description
- Click to expand check and see full system prompt
- Expand All / Collapse All buttons

## Key Principles

1. **true = failure detected** - Checks are written to catch problems
2. **na only when inapplicable** - Not when check passes, only when scenario didn't occur
3. **Step-by-step for complex logic** - Helps grader model follow evaluation correctly
4. **One failure mode per check** - Atomic, not compound conditions
5. **Observable in trace** - Must be verifiable from tool calls and messages
6. **Explicit about tool names** - Reference exact tool names from agent source
7. **Line-citable** - If you can't Ctrl+F the evidence in the trace, it's not valid
