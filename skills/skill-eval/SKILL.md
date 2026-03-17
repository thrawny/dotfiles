---
name: skill-eval
description: Evaluate and optimize skill description triggering accuracy. Use when the user wants to test whether a skill's description triggers correctly, benchmark trigger rates, or iteratively improve a skill description. Works entirely via claude -p (no API key needed).
---

# skill-eval

Evaluate and iteratively improve skill descriptions using only `claude -p` (subscription auth, no API key).

## Workflow

### 1. Generate eval queries

Create 20 should-trigger/should-not-trigger test prompts. Draft them as a JSON array:

```json
[
  {"query": "realistic user prompt that should trigger", "should_trigger": true},
  {"query": "realistic near-miss that should NOT trigger", "should_trigger": false}
]
```

Aim for 10 should-trigger and 10 should-not-trigger. Make queries realistic and detailed — not abstract. Focus on edge cases, not obvious ones.

### 2. Review eval queries with the user

Use the HTML template at `assets/eval_review.html` to let the user review and edit queries:

1. Read the template
2. Replace placeholders:
   - `__EVAL_DATA_PLACEHOLDER__` with the JSON array (no quotes — it's a JS variable)
   - `__SKILL_NAME_PLACEHOLDER__` with the skill name
   - `__SKILL_DESCRIPTION_PLACEHOLDER__` with the current description
3. Write to `/tmp/eval_review_<skill-name>.html` and open with `xdg-open`
4. User edits queries, clicks "Export Eval Set" — downloads `eval_set.json` to `~/Downloads/`

### 3. Run eval + improve

```bash
# Eval only
python skills/skill-eval/scripts/eval_skill.py \
  --eval-set path/to/eval_set.json \
  --skill-path skills/<skill-name> \
  --model claude-opus-4-6

# Eval + improve loop
python skills/skill-eval/scripts/eval_skill.py \
  --eval-set path/to/eval_set.json \
  --skill-path skills/<skill-name> \
  --model claude-opus-4-6 \
  --improve \
  --max-iterations 3
```

Use `--model` matching the current session's model ID. Run in the background for long evals.

### 4. Apply the result

Take the `best_description` from the JSON output and update the skill's SKILL.md frontmatter.

## How it works

- Eval step uses `claude -p` with `--setting-sources "project,local"` to suppress global skills, preventing the real skill from competing with the test command
- Each query runs in an isolated temp directory with only the test command file
- Improvement step uses `claude -p` to propose better descriptions (no `ANTHROPIC_API_KEY` needed)
- 60s default timeout (Opus needs more time than Sonnet)
- Scans all tool calls in the response (doesn't bail early on ToolSearch/Bash calls before Skill)
