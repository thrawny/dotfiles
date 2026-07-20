#!/usr/bin/env python3
"""Claude Code status line: minimal flat, monokai, starship-style git status."""

# pyright: basic

import json
import os
import subprocess
import sys

# Monokai
CYAN = "66d9ef"
YELLOW = "e6db74"
ORANGE = "fd971f"
RED = "f92672"
GRAY = "75715e"
LIGHT_GRAY = "a59f85"
LINE = "49483e"

RESET = "\033[0m"
BOLD = "\033[1m"

BRANCH_GLYPH = ""
BOLT = ""


def fg(hex_color: str) -> str:
    r = int(hex_color[0:2], 16)
    g = int(hex_color[2:4], 16)
    b = int(hex_color[4:6], 16)
    return f"\033[38;2;{r};{g};{b}m"


DIVIDER = f" {fg(LINE)}│{RESET} "


def get_git_info() -> tuple[str | None, str]:
    """Return (branch, starship-style status symbols) from one porcelain call."""
    try:
        result = subprocess.run(
            ["git", "--no-optional-locks", "status", "--porcelain=v2", "--branch"],
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return (None, "")
    if result.returncode != 0:
        return (None, "")

    branch: str | None = None
    ahead = behind = 0
    conflicted = deleted = renamed = modified = staged = untracked = False

    for line in result.stdout.splitlines():
        if line.startswith("# branch.head "):
            head = line[len("# branch.head ") :]
            branch = None if head == "(detached)" else head
        elif line.startswith("# branch.ab "):
            parts = line.split()
            ahead = int(parts[2])
            behind = abs(int(parts[3]))
        elif line.startswith(("1 ", "2 ")):
            xy = line.split(" ", 2)[1]
            x, y = xy[0], xy[1]
            if x == "R" or y == "R":
                renamed = True
            if x == "D" or y == "D":
                deleted = True
            if x not in ".RD":
                staged = True
            if y not in ".RD":
                modified = True
        elif line.startswith("u "):
            conflicted = True
        elif line.startswith("? "):
            untracked = True

    symbols = ""
    if conflicted:
        symbols += "="
    if deleted:
        symbols += "✘"
    if renamed:
        symbols += "»"
    if modified:
        symbols += "!"
    if staged:
        symbols += "+"
    if untracked:
        symbols += "?"
    if ahead and behind:
        symbols += "⇕"
    elif ahead:
        symbols += "⇡"
    elif behind:
        symbols += "⇣"

    return (branch, symbols)


def env_flag_set(name: str) -> bool:
    """Return True when an env flag is set to a truthy value."""
    value = os.getenv(name)
    if not value:
        return False
    return value.strip().lower() not in {"0", "false"}


def get_runtime_badge() -> str | None:
    """Badge for the current runtime environment."""
    if env_flag_set("SANDBOX"):
        return "\U0001fae7"  # 🫧

    incus_container = os.getenv("INCUS_CONTAINER", "").strip()
    if incus_container:
        return f"\U0001f433 {fg(LIGHT_GRAY)}{incus_container}{RESET}"  # 🐳 name

    return None


def format_tokens(tokens: int) -> str:
    """Format token count nicely."""
    if tokens >= 1_000_000:
        return f"{tokens / 1_000_000:.1f}M"
    elif tokens >= 1000:
        return f"{tokens / 1000:.1f}k"
    return str(tokens)


def truncate(text: str, max_len: int = 20) -> str:
    """Truncate text with ellipsis."""
    if len(text) > max_len:
        return text[: max_len - 1] + "…"
    return text


def get_context_from_input(data: dict) -> tuple[int, float] | None:
    """Extract context info from Claude Code input (new API)."""
    if "context_window" in data:
        cw = data["context_window"]
        api_percentage = cw.get("used_percentage")
        window_size = cw.get("context_window_size", 200_000)
        if api_percentage is not None:
            tokens = int(window_size * api_percentage / 100)
            return (tokens, api_percentage)
    return None


def get_context_from_transcript(
    transcript_path: str, window_size: int = 200_000
) -> tuple[int, float] | None:
    """Fallback: parse transcript for context info."""
    try:
        with open(transcript_path) as f:
            lines = f.read().strip().split("\n")

        for line in reversed(lines):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                if (
                    obj.get("type") == "assistant"
                    and "message" in obj
                    and "usage" in obj["message"]
                    and "input_tokens" in obj["message"]["usage"]
                ):
                    usage = obj["message"]["usage"]
                    tokens = (
                        usage.get("input_tokens", 0)
                        + usage.get("cache_creation_input_tokens", 0)
                        + usage.get("cache_read_input_tokens", 0)
                    )
                    percentage = min(100, (tokens / window_size) * 100)
                    return (tokens, percentage)
            except (json.JSONDecodeError, KeyError):
                continue
    except OSError:
        pass
    return None


def main() -> None:
    data = json.load(sys.stdin)

    model = data.get("model", {}).get("display_name", "Claude")
    model = model.replace("Claude ", "")  # Shorten "Claude Opus 4.5" to "Opus 4.5"

    window_size = data.get("context_window", {}).get("context_window_size", 200_000)
    context_info = get_context_from_input(data)
    if not context_info and "transcript_path" in data:
        context_info = get_context_from_transcript(data["transcript_path"], window_size)

    parts = [f"{BOLD}{fg(CYAN)}{model}{RESET}"]

    if context_info:
        tokens, percentage = context_info
        # Percentage is against the auto-compact window when one is configured,
        # not the model's full context window.
        compact_window = os.getenv("CLAUDE_CODE_AUTO_COMPACT_WINDOW", "")
        if compact_window.isdigit() and int(compact_window) > 0:
            percentage = min(100, tokens / int(compact_window) * 100)
        text = f"{format_tokens(tokens)} {percentage:.0f}%"
        if percentage >= 90:
            parts.append(f"{BOLD}{fg(RED)}{BOLT} {text}{RESET}")
        elif percentage >= 80:
            parts.append(f"{fg(ORANGE)}{text}{RESET}")
        else:
            parts.append(f"{fg(GRAY)}{text}{RESET}")

    branch, symbols = get_git_info()
    if branch:
        git_part = f"{fg(YELLOW)}{BRANCH_GLYPH} {truncate(branch)}{RESET}"
        if symbols:
            git_part += f" {fg(ORANGE)}{symbols}{RESET}"
        parts.append(git_part)

    badge = get_runtime_badge()
    if badge:
        parts.append(badge)

    print(DIVIDER.join(parts))


if __name__ == "__main__":
    main()
