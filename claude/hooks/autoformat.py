#!/usr/bin/env python3
"""
Multi-language autoformatter hook for Claude Code.
Runs appropriate formatters based on file extension.
"""

import json
import subprocess
import sys
from pathlib import Path
from typing import Any, TypedDict


class HookInput(TypedDict, total=False):
    """Type definition for Claude hook input."""

    hook_event_name: str
    tool_name: str
    tool_input: dict[str, Any]


class Checker(TypedDict):
    """Type definition for a code checker/formatter."""

    name: str  # Friendly display name
    command: list[str]  # Command to run with {file} placeholder


# Formatter configuration
# Each extension maps to a list of checkers to run in sequence
FORMATTERS: dict[str, list[Checker]] = {
    # Python
    ".py": [
        {
            "name": "Ruff Linter",
            "command": ["ruff", "check", "--fix", "--unfixable", "F401", "{file}"],
        },
        {"name": "Ruff Formatter", "command": ["ruff", "format", "{file}"]},
        {"name": "Type Checker", "command": ["basedpyright", "{file}"]},
    ],
    # Go
    # ".go": [
    #     {
    #         "name": "Go Linter",
    #         "command": ["golangci-lint", "run", "--fast-only", "--fix", "{file}"],
    #     },
    #     {
    #         "name": "Go Formatter",
    #         "command": [
    #             "golangci-lint",
    #             "fmt",
    #             "--enable=gofmt",
    #             "--enable=gofumpt",
    #             "--enable=gci",
    #             "{file}",
    #         ],
    #     },
    # ],
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


def run_formatter(checker: Checker, file_path: str) -> tuple[bool, str, str]:
    """
    Run a single formatter command.
    Returns (success, output_message, detailed_output).
    """
    name = checker["name"]
    cmd_template = checker["command"]

    # Replace {file} placeholder with actual file path
    cmd = [part.replace("{file}", file_path) for part in cmd_template]

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


def format_file(file_path: str) -> None:
    """Format a file based on its extension."""
    path = Path(file_path)

    # Check if file exists
    if not path.exists():
        print(f"⚠️  File not found: {file_path}")
        return

    # Get file extension
    ext = path.suffix.lower()

    # Check if we have formatters for this extension
    if ext not in FORMATTERS:
        # Silent skip for unsupported file types
        return

    print(f"\n{'=' * 60}")
    print(f"🎨 Auto-formatting: {path.name}")
    print(f"{'=' * 60}")

    # Run all formatters for this file type
    all_success = True
    has_unfixable_issues = False
    unfixable_details: list[str] = []

    for checker in FORMATTERS[ext]:
        success, message, details = run_formatter(checker, file_path)
        print(message)

        # Show details for issues
        if details and not success:
            has_unfixable_issues = True
            unfixable_details.append(details)
        elif details and "Fixed" in message:
            # Show what was fixed
            lines = details.split("\n")
            for line in lines[:10]:  # Show first 10 lines of fixes
                if line.strip():
                    print(f"    {line}")
            if len(lines) > 10:
                print(f"    ... and {len(lines) - 10} more fixes")

        if not success:
            all_success = False

    # Final status
    print(f"{'-' * 60}")
    if has_unfixable_issues:
        print(f"⚠️  {path.name} has issues that need manual fixing:")
        for details in unfixable_details:
            # Show the actual errors that need fixing
            for line in details.split("\n"):
                if line.strip():
                    print(f"    {line}")
    elif all_success:
        print(f"✨ {path.name} formatted successfully!")
    else:
        print(f"⚠️  {path.name} formatting completed with warnings")
    print(f"{'=' * 60}\n")


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
    if tool_name not in ["Write", "Edit", "MultiEdit"]:
        sys.exit(0)

    # Handle different tool types
    if tool_name in ["Write", "Edit"]:
        # Single file operation
        file_path_input = tool_input.get("file_path", "")
        if file_path_input and isinstance(file_path_input, str):
            format_file(file_path_input)

    elif tool_name == "MultiEdit":
        # Multiple files potentially affected
        # MultiEdit typically operates on a single file but check for file_path
        multi_file_path = tool_input.get("file_path", "")
        if multi_file_path and isinstance(multi_file_path, str):
            format_file(multi_file_path)

    # Always exit 0 for PostToolUse (can't block operation)
    sys.exit(0)


if __name__ == "__main__":
    main()
