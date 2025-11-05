#!/usr/bin/env python3
"""
Claude Code Hook: Bash Command Validator
=========================================
This hook runs as a PreToolUse hook for the Bash tool.
It validates bash commands against project-specific conventions:
- Prefer golangci-lint over goimports
- Enforce proper go build output paths
- Use uv instead of pip for Python dependencies

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
            "command": "python3 ~/dotfiles/config/claude/hooks/bash_command.py"
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

# Define validation rules for project-specific conventions
_VALIDATION_RULES = [
    (
        r"^goimports\s+-w\b",
        "Use 'golangci-lint run --fix' instead of goimports -w for comprehensive Go formatting and linting",
    ),
    (
        r"^go\s+build\b(?!.*\s-o\s)",
        "Use 'go build -o build/binary_name' to specify output location, or use 'go run' instead to avoid creating untracked binaries",
    ),
    (
        r"^go\s+build\b.*\s-o\s+(?!(?:build|bin|dist|out|target|\.build|tmp|/)[/\w])",
        "Use 'go build -o build/binary_name' with a proper path (e.g., build/, bin/, dist/) to avoid cluttering the project root with binaries",
    ),
    (
        r"(?:^|&&\s*)pip\s+install\b",
        "Use 'uv add <package>' instead of pip install for better dependency management and faster installation",
    ),
]


def _validate_command(command: str) -> list[str]:
    issues: list[str] = []
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

    # Validate command against project-specific rules
    issues = _validate_command(command)

    if issues:
        for message in issues:
            print(f"• {message}", file=sys.stderr)
        # Exit code 2 blocks tool call and shows stderr to Claude
        sys.exit(2)


if __name__ == "__main__":
    main()
