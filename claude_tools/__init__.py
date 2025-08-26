"""Claude Tools - Simple and direct tools for Claude Code automation."""

from .core import (
    calculate_session_timing,
    generate_session_id,
    run_claude_query,
    run_claude_task,
    run_five_step_iteration,
    run_work_session,
)
from .prompts import (
    CONTINUE_TASK_PROMPT,
    LONG_TASK_SYSTEM_PROMPT,
    WORKFLOW_PROMPTS,
    WRAP_UP_PROMPT,
)

__all__ = [
    "generate_session_id",
    "calculate_session_timing",
    "run_claude_query",
    "run_claude_task",
    "run_five_step_iteration",
    "run_work_session",
    "LONG_TASK_SYSTEM_PROMPT",
    "CONTINUE_TASK_PROMPT",
    "WRAP_UP_PROMPT",
    "WORKFLOW_PROMPTS",
]
