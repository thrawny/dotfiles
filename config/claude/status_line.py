#!/usr/bin/env python3
"""Claude Code status line with powerline styling and nerd font symbols."""

import json
import os
import subprocess
import sys

# Powerline symbols (nerd font) - rounded style
SEP = "\ue0b4"  # Rounded right arrow separator
START_CAP = "\ue0b6"  # Rounded left cap
END_CAP = "\ue0b4"  # Rounded right cap


def hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    """Convert hex color to RGB tuple."""
    return (
        int(hex_color[0:2], 16),
        int(hex_color[2:4], 16),
        int(hex_color[4:6], 16),
    )


def fg_true(hex_color: str) -> str:
    """True color foreground."""
    r, g, b = hex_to_rgb(hex_color)
    return f"\033[38;2;{r};{g};{b}m"


def bg_true(hex_color: str) -> str:
    """True color background."""
    r, g, b = hex_to_rgb(hex_color)
    return f"\033[48;2;{r};{g};{b}m"


# Color scheme (fg_hex, bg_hex)
WHITE = "ffffff"
BLACK = "000000"
RED = "ae605e"
YELLOW = "ffd602"
BLUE = "5f87d7"
GREEN = "87af87"

COLORS = {
    "model": (WHITE, RED),
    "tokens": (BLACK, YELLOW),
    "percentage": (BLACK, YELLOW),
    "percentage_warn": (BLACK, YELLOW),
    "percentage_crit": (WHITE, RED),
    "branch": (WHITE, BLUE),
    "changes": (BLACK, GREEN),
}


def reset() -> str:
    return "\033[0m"


def segment(text: str, fg_color: str, bg_color: str, next_bg: str | None = None) -> str:
    """Create a powerline segment with rounded separator."""
    result = f"{fg_true(fg_color)}{bg_true(bg_color)} {text} "
    if next_bg:
        result += f"{fg_true(bg_color)}{bg_true(next_bg)}{SEP}"
    else:
        # Last segment - use rounded end cap
        result += f"{reset()}{fg_true(bg_color)}{END_CAP}{reset()}"
    return result


def get_git_branch() -> str | None:
    """Get the current git branch name."""
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

    # Fallback: read .git/HEAD directly
    if os.path.exists(".git"):
        try:
            if os.path.isfile(".git"):
                with open(".git") as f:
                    gitdir_line = f.read().strip()
                    if gitdir_line.startswith("gitdir: "):
                        gitdir = gitdir_line[8:]
                        head_file = os.path.join(gitdir, "HEAD")
                        if os.path.exists(head_file):
                            with open(head_file) as f:
                                ref = f.read().strip()
                                if ref.startswith("ref: refs/heads/"):
                                    return ref.replace("ref: refs/heads/", "")
            else:
                with open(".git/HEAD") as f:
                    ref = f.read().strip()
                    if ref.startswith("ref: refs/heads/"):
                        return ref.replace("ref: refs/heads/", "")
        except OSError:
            pass
    return None


def get_git_changes() -> tuple[int, int] | None:
    """Get git changes as (added, removed) line counts."""
    try:
        result = subprocess.run(
            ["git", "diff", "--shortstat"],
            capture_output=True,
            text=True,
            timeout=2,
        )
        if result.returncode == 0 and result.stdout.strip():
            output = result.stdout.strip()
            added = removed = 0
            if "insertion" in output:
                for part in output.split(","):
                    if "insertion" in part:
                        added = int(part.split()[0])
                    elif "deletion" in part:
                        removed = int(part.split()[0])
            elif "deletion" in output:
                for part in output.split(","):
                    if "deletion" in part:
                        removed = int(part.split()[0])
            return (added, removed)
        return (0, 0)
    except (
        subprocess.TimeoutExpired,
        subprocess.CalledProcessError,
        FileNotFoundError,
    ):
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
        percentage = cw.get("used_percentage")
        window_size = cw.get("context_window_size", 200000)
        if percentage is not None:
            # Calculate actual current context from percentage
            tokens = int(window_size * percentage / 100)
            return (tokens, float(percentage))
    return None


def get_context_from_transcript(transcript_path: str) -> tuple[int, float] | None:
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
                    percentage = min(100, (tokens / 200_000) * 100)
                    return (tokens, percentage)
            except (json.JSONDecodeError, KeyError):
                continue
    except OSError:
        pass
    return None


def main() -> None:
    data = json.load(sys.stdin)

    # Model name
    model = data.get("model", {}).get("display_name", "Claude")
    model = model.replace("Claude ", "")  # Shorten "Claude Opus 4.5" to "Opus 4.5"

    # Context info (try new API first, fallback to transcript)
    context_info = get_context_from_input(data)
    if not context_info and "transcript_path" in data:
        context_info = get_context_from_transcript(data["transcript_path"])

    # Git info
    branch = get_git_branch()
    changes = get_git_changes()

    # Build segments
    segments = []

    # Determine what segments we have and calculate context colors
    has_branch = branch is not None
    has_changes = changes is not None

    # Calculate context colors based on usage percentage
    ctx_colors: tuple[str, str] | None = None
    if context_info:
        _, percentage = context_info
        if percentage >= 90:
            ctx_colors = COLORS["percentage_crit"]
        elif percentage >= 75:
            ctx_colors = COLORS["percentage_warn"]
        else:
            ctx_colors = COLORS["percentage"]

    # Model segment
    if ctx_colors:
        next_bg = ctx_colors[1]
    elif has_branch:
        next_bg = COLORS["branch"][1]
    elif has_changes:
        next_bg = COLORS["changes"][1]
    else:
        next_bg = None
    segments.append(segment(model, *COLORS["model"], next_bg))

    # Context segment (tokens + percentage)
    if context_info and ctx_colors:
        tokens, percentage = context_info
        token_str = format_tokens(tokens)

        if has_branch:
            next_bg = COLORS["branch"][1]
        elif has_changes:
            next_bg = COLORS["changes"][1]
        else:
            next_bg = None
        segments.append(
            segment(
                f"{token_str} {percentage:.1f}%", ctx_colors[0], ctx_colors[1], next_bg
            )
        )

    # Git branch segment
    if branch:
        if has_changes:
            next_bg = COLORS["changes"][1]
        else:
            next_bg = None
        segments.append(
            segment(f"\ue0a0 {truncate(branch)}", *COLORS["branch"], next_bg)
        )

    # Git changes segment
    if changes:
        added, removed = changes
        segments.append(segment(f"+{added}, -{removed}", *COLORS["changes"], None))

    # Output with rounded start cap
    output = f"{fg_true(COLORS['model'][1])}{START_CAP}{reset()}"
    output += "".join(segments)
    print(output)


if __name__ == "__main__":
    main()
