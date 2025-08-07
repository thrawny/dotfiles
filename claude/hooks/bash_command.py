#!/usr/bin/env python3
"""
Claude Code Hook: Bash Command Validator
=========================================
This hook runs as a PreToolUse hook for the Bash tool.
It validates bash commands against a set of rules before execution.
In this case it changes grep calls to using rg.

Read more about hooks here: https://docs.anthropic.com/en/docs/claude-code/hooks

Make sure to change your path to your actual script.

{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 ~/dotfiles/claude/hooks/bash_command.py"
          }
        ]
      }
    ]
  }
}

"""

import json
import re
import sys

# Define validation rules as a list of (regex pattern, message) tuples
_VALIDATION_RULES = [
    (
        r"^grep\b(?!.*(?<!\|)\|(?!\|))",
        "Use the 'Grep' tool instead of bash grep for better integration and features",
    ),
    (
        r"^rg\b(?!.*\|)",
        "Use the 'Grep' tool instead of raw rg commands for better integration",
    ),
    (
        r"^find\s+.*-name\b",
        "Use the 'Glob' tool with patterns like '**/*.ext' or '**/filename*' instead of find -name commands",
    ),
    (
        r"^find\s+.*-type\s+f",
        "Use the 'Glob' tool with patterns like '**/*' or '**/*.ext' instead of find -type f commands",
    ),
    (
        r"^ls\s+",
        "Use the 'LS' tool with path parameter instead of bash ls for structured output",
    ),
    (
        r"^cat\s+",
        "Use the 'Read' tool with file_path parameter instead of cat for syntax highlighting and line numbers",
    ),
    (
        r"^head\s+",
        "Use the 'Read' tool with limit parameter (e.g., limit=10) instead of head",
    ),
    (
        r"^tail\s+",
        "Use the 'Read' tool with negative offset parameter (e.g., offset=-10) to read from end instead of tail",
    ),
    (
        r"^goimports\s+-w\b",
        "Use 'golangci-lint run --fix' instead of goimports -w for comprehensive Go formatting and linting",
    ),
    (
        r"^grep\b.*\|.*\btail\b",
        "Use the 'Grep' tool with output_mode='content', -n=true, and head_limit parameter instead of piped grep commands",
    ),
    (
        r"^sed\s+",
        "Use the 'Edit' tool with old_string/new_string parameters or 'MultiEdit' for multiple replacements instead of sed",
    ),
]

# Hook did not catch this:
# grep -n "func Test" /Users/jonas/code/kf1-go/internal/device/weco_hybo_test.go | tail -1
# sed -i '' 's/positive = import, negative = export/negative = import, positive = export (PyControl convention)/g' /Users/jonas/code/kf1-go/internal/domain/device.go


def _validate_command(command: str) -> list[str]:
    issues = []
    for pattern, message in _VALIDATION_RULES:
        if re.search(pattern, command):
            issues.append(message)
    return issues


def main():
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
        # Exit code 1 shows stderr to the user but not to Claude
        sys.exit(1)

    tool_name = input_data.get("tool_name", "")
    if tool_name != "Bash":
        sys.exit(0)

    tool_input = input_data.get("tool_input", {})
    command = tool_input.get("command", "")

    if not command:
        sys.exit(0)

    issues = _validate_command(command)
    if issues:
        for message in issues:
            print(f"• {message}", file=sys.stderr)
        # Exit code 2 blocks tool call and shows stderr to Claude
        sys.exit(2)


if __name__ == "__main__":
    main()
