"""Claude Tools - Simple and direct tools for Claude Code automation."""

from .core import (
    calculate_session_timing,
    generate_session_id,
)
from .prompts import (
    CONTINUE_TASK_PROMPT,
    LONG_TASK_SYSTEM_PROMPT,
    WRAP_UP_PROMPT,
)

__all__ = [
    "generate_session_id",
    "calculate_session_timing",
    "LONG_TASK_SYSTEM_PROMPT",
    "CONTINUE_TASK_PROMPT",
    "WRAP_UP_PROMPT",
]
