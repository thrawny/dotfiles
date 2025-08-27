#!/usr/bin/env python3
import json
import os
import subprocess
import sys
from typing import Any

# Read JSON from stdin
data = json.load(sys.stdin)

# Extract values
model = data["model"]["display_name"]
current_dir = os.path.basename(data["workspace"]["current_dir"])


# Calculate current context size from transcript
def calculate_context_tokens(transcript_path: str) -> dict[str, int] | None:
    """Calculate the current context size from the transcript file using actual token counts"""
    try:
        # Read the transcript file
        with open(transcript_path, "r") as f:
            content = f.read()

        # Split into lines and iterate from last to first (most recent first)
        lines = content.strip().split("\n")

        for line in reversed(lines):
            line = line.strip()
            if not line:
                continue

            try:
                # Parse the JSON line
                obj = json.loads(line)

                # Check if this is an assistant message with usage data
                if (
                    obj.get("type") == "assistant"
                    and "message" in obj
                    and "usage" in obj["message"]
                    and "input_tokens" in obj["message"]["usage"]
                ):
                    usage = obj["message"]["usage"]
                    # Calculate total input tokens including cache tokens
                    input_tokens = (
                        usage.get("input_tokens", 0)
                        + usage.get("cache_creation_input_tokens", 0)
                        + usage.get("cache_read_input_tokens", 0)
                    )

                    # Calculate percentage of context used (150k limit for compact warnings)
                    percentage = min(100, max(0, round((input_tokens / 150000) * 100)))

                    return {
                        "tokens": input_tokens,
                        "percentage": percentage,
                    }
            except (json.JSONDecodeError, KeyError):
                # Skip malformed JSON lines
                continue

        # No usage data found
        return None

    except Exception:
        # If we can't read the transcript, return None
        return None


def calculate_context_size(session_data: dict[str, Any]) -> dict[str, int] | None:
    """Calculate the current context size being sent to Claude"""
    # Check if we have transcript_path
    if "transcript_path" in session_data:
        result = calculate_context_tokens(session_data["transcript_path"])
        if result:
            return result

    return None


def truncate_branch_name(branch: str, max_length: int = 20) -> str:
    """Truncate branch name if it's too long"""
    if len(branch) > max_length:
        return branch[: max_length - 3] + "..."
    return branch


def get_git_branch() -> str | None:
    """Get the current git branch name, trying multiple methods"""
    # Try method 1: use git command
    try:
        result = subprocess.run(
            ["git", "symbolic-ref", "--short", "HEAD"],
            capture_output=True,
            text=True,
            timeout=1,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (
        subprocess.TimeoutExpired,
        subprocess.CalledProcessError,
        FileNotFoundError,
    ):
        pass

    # Try method 2 & 3: read from .git files
    if os.path.exists(".git"):
        try:
            # Check if .git is a file (worktree) or directory (regular repo)
            if os.path.isfile(".git"):
                # It's a worktree - read the gitdir path
                with open(".git", "r") as f:
                    gitdir_line = f.read().strip()
                    if gitdir_line.startswith("gitdir: "):
                        gitdir = gitdir_line[8:]
                        head_file = os.path.join(gitdir, "HEAD")
                        if os.path.exists(head_file):
                            with open(head_file, "r") as f:
                                ref = f.read().strip()
                                if ref.startswith("ref: refs/heads/"):
                                    return ref.replace("ref: refs/heads/", "")
            else:
                # Regular repo
                with open(".git/HEAD", "r") as f:
                    ref = f.read().strip()
                    if ref.startswith("ref: refs/heads/"):
                        return ref.replace("ref: refs/heads/", "")
        except:  # noqa: E722
            pass

    return None


# Get current context size
context_info = ""
context_data = calculate_context_size(data)
if context_data:
    tokens = context_data["tokens"]
    percentage = context_data["percentage"]

    # Format context display (use K for thousands, M for millions)
    if tokens >= 1000000:
        token_display = f"{tokens / 1000000:.1f}M"
    elif tokens >= 1000:
        token_display = f"{tokens / 1000:.1f}K"
    else:
        token_display = str(tokens)

    # Add percentage if significant (>86% which is ~130k tokens with 150k base)
    if percentage >= 86:
        # Show percentage with color coding
        if percentage >= 93:  # ~140k tokens
            context_info = f" | 📝 {token_display} ({percentage}%‼️)"
        else:  # ~130k-140k tokens
            context_info = f" | 📝 {token_display} ({percentage}%⚠️)"
    else:
        context_info = f" | 📝 {token_display}"

# Get git branch and format it
branch = get_git_branch()
git_branch = ""
if branch:
    git_branch = f" | 🌿 {truncate_branch_name(branch)}"

print(f"[{model}] 📁 {current_dir}{git_branch}{context_info}")
