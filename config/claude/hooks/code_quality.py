#!/usr/bin/env python3
"""
Code quality hook for Claude Code.
Runs linters and type checkers based on file extension.
"""

import json
import subprocess
import sys
from pathlib import Path
from typing import Any, Required, TypedDict


class HookInput(TypedDict, total=False):
    """Type definition for Claude hook input."""

    hook_event_name: str
    tool_name: str
    tool_input: dict[str, Any]


class Checker(TypedDict, total=False):
    """Type definition for a code checker/formatter."""

    name: Required[str]  # Friendly display name
    command: Required[list[str]]  # Command to run with {file} placeholder
    json_output: bool  # If True, parse JSON output and filter issues
    exclude_patterns: list[str]  # Patterns to exclude from JSON output


# Formatter configuration
# Each extension maps to a list of checkers to run in sequence
FORMATTERS: dict[str, list[Checker]] = {
    # Python
    ".py": [
        {
            "name": "Ruff Linter",
            "command": ["ruff", "check", "--ignore", "F401,F841,I001", "{file}"],
        },
        # {"name": "Ruff Formatter", "command": ["ruff", "format", "{file}"]},
        {
            "name": "Type Checker",
            "command": ["basedpyright", "--level", "error", "{file}"],
        },
    ],
    # Go - linting only (no formatting to avoid disrupting agent workflow)
    # Uses JSON output + filtering to exclude unused imports/variables
    ".go": [
        {
            "name": "Go Linter",
            "command": [
                "golangci-lint",
                "run",
                "--output.json.path=stdout",
                "--disable=unused",
            ],
            "json_output": True,
            "exclude_patterns": [
                "imported and not used",
                "declared and not used",
                "declared but not used",
            ],
        },
    ],
    # Add more languages here as needed:
    # ".rs": [["rustfmt", "{file}"]],
    # ".js": [["prettier", "--write", "{file}"]],
    # ".ts": [["prettier", "--write", "{file}"]],
    # ".tsx": [["prettier", "--write", "{file}"]],
    # ".jsx": [["prettier", "--write", "{file}"]],
    # ".json": [["prettier", "--write", "{file}"]],
    # ".yaml": [["prettier", "--write", "{file}"]],
    # ".yml": [["prettier", "--write", "{file}"]],
    # ".md": [["prettier", "--write", "{file}"]],
}


def check_command_exists(cmd: str) -> bool:
    """Check if a command is available in PATH."""
    result = subprocess.run(["which", cmd], capture_output=True, text=True)
    return result.returncode == 0


class LintIssue(TypedDict, total=False):
    """Type definition for a lint issue from JSON output."""

    FromLinter: str
    Text: str
    Pos: dict[str, Any]


def filter_json_issues(
    stdout: str, exclude_patterns: list[str]
) -> tuple[list[LintIssue], str]:
    """
    Parse JSON output and filter out issues matching exclude patterns.
    Returns (filtered_issues, formatted_output).
    """
    try:
        # Find the JSON object (skip any trailing text like "6 issues:")
        json_end = stdout.rfind("}") + 1
        if json_end == 0:
            return [], stdout
        json_str = stdout[:json_end]
        data: dict[str, Any] = json.loads(json_str)
    except json.JSONDecodeError:
        return [], stdout

    issues: list[LintIssue] = data.get("Issues", [])
    if not issues:
        return [], ""

    # Filter out excluded patterns
    filtered: list[LintIssue] = []
    for issue in issues:
        text = issue.get("Text", "")
        if not any(pattern in text for pattern in exclude_patterns):
            filtered.append(issue)

    if not filtered:
        return [], ""

    # Format remaining issues for display
    lines: list[str] = []
    for issue in filtered:
        pos = issue.get("Pos", {})
        filename: str = pos.get("Filename", "?")
        line: int = pos.get("Line", 0)
        col: int = pos.get("Column", 0)
        text = issue.get("Text", "")
        linter = issue.get("FromLinter", "")
        lines.append(f"    {filename}:{line}:{col}: {text} ({linter})")

    return filtered, "\n".join(lines)


def run_formatter(checker: Checker, file_path: str) -> tuple[bool, str, str]:
    """
    Run a single formatter command.
    Returns (success, output_message, detailed_output).
    """
    name = checker["name"]
    cmd_template = checker["command"]
    use_json = checker.get("json_output", False)
    exclude_patterns = checker.get("exclude_patterns", [])

    # Determine the target path for the command based on placeholder
    # {file_path} -> directory path (for tools that operate on packages like golangci-lint)
    # {file} -> file path (for tools that operate on individual files)
    path = Path(file_path)
    cmd_str = " ".join(cmd_template)

    if "{file_path}" in cmd_str:
        # Replace {file_path} with directory path
        cmd = [part.replace("{file_path}", str(path.parent)) for part in cmd_template]
    elif "{file}" in cmd_str:
        # Replace {file} with file path
        cmd = [part.replace("{file}", file_path) for part in cmd_template]
    else:
        # No placeholder, use template as-is
        cmd = list(cmd_template)

    # Check if command exists
    if not check_command_exists(cmd[0]):
        return True, f"  ⚠️  {name} ({cmd[0]}) not found, skipping", ""

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,  # 30 second timeout
        )

        # Handle JSON output with filtering
        if use_json and result.stdout:
            filtered_issues, formatted_output = filter_json_issues(
                result.stdout, exclude_patterns
            )
            if not filtered_issues:
                return True, f"  ✅ {name}: No issues found", ""
            return (
                False,
                f"  ⚠️  {name}: Found {len(filtered_issues)} issue(s)",
                formatted_output,
            )

        # Collect both stdout and stderr for diagnostics
        detailed_output = ""
        if result.stdout and result.stdout.strip():
            detailed_output = result.stdout.strip()
        if result.stderr and result.stderr.strip():
            if detailed_output:
                detailed_output += "\n"
            detailed_output += result.stderr.strip()

        if result.returncode == 0:
            # Check if this was ruff check that found and fixed issues
            if "ruff" in cmd[0] and "check" in cmd and "Found" in detailed_output:
                # Extract fix summary if available
                return (
                    True,
                    f"  ✅ {name}: Fixed issues automatically",
                    detailed_output,
                )
            elif detailed_output:
                return True, f"  ✅ {name}: Clean", ""
            else:
                return True, f"  ✅ {name}: No issues found", ""
        else:
            # Non-zero exit code means there are unfixable issues
            return (
                False,
                f"  ⚠️  {name}: Found issues that need manual fixing",
                detailed_output,
            )

    except subprocess.TimeoutExpired:
        return False, f"  ⏱️  {name} timed out", ""
    except Exception as e:
        return False, f"  ❌ {name} error: {e}", ""


def format_file(file_path: str) -> bool:
    """
    Format a file based on its extension.
    Returns True if there are unfixable issues that need attention.
    """
    path = Path(file_path)

    # Check if file exists
    if not path.exists():
        print(f"⚠️  File not found: {file_path}", file=sys.stderr)
        return False

    # Get file extension
    ext = path.suffix.lower()

    # Check if we have formatters for this extension
    if ext not in FORMATTERS:
        # Silent skip for unsupported file types
        return False

    # Run all formatters for this file type
    has_unfixable_issues = False
    unfixable_details: list[str] = []

    for checker in FORMATTERS[ext]:
        success, _, details = run_formatter(checker, file_path)
        if details and not success:
            has_unfixable_issues = True
            unfixable_details.append(details)

    # Only print if there are issues
    if has_unfixable_issues:
        print(f"\n⚠️  {path.name} has issues:", file=sys.stderr)
        for details in unfixable_details:
            for line in details.split("\n"):
                if line.strip():
                    print(f"  {line}", file=sys.stderr)

    return has_unfixable_issues


def main() -> None:
    """Main hook entry point."""
    # Read input from stdin
    try:
        input_data: HookInput = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error parsing input: {e}", file=sys.stderr)
        sys.exit(1)

    # Extract hook data
    hook_event = input_data.get("hook_event_name", "")
    tool_name = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})

    # Only process PostToolUse events
    if hook_event != "PostToolUse":
        sys.exit(0)

    # Check if this is a write/edit operation
    if tool_name not in ["Write", "Edit"]:
        sys.exit(0)

    # Handle different tool types
    has_issues = False
    if tool_name in ["Write", "Edit"]:
        # Single file operation
        file_path_input = tool_input.get("file_path", "")
        if file_path_input and isinstance(file_path_input, str):
            has_issues = format_file(file_path_input)

    # Exit with code 2 if there are unfixable issues (feeds output to Claude)
    # Exit with code 0 if everything is clean (output only shown to user)
    if has_issues:
        sys.exit(2)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()
