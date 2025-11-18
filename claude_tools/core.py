"""Core functionality for Claude Tools."""

import uuid
from collections.abc import AsyncIterator
from datetime import datetime, timedelta
from typing import Any, Callable

import asyncclick as click
from claude_agent_sdk import AssistantMessage, TextBlock


def generate_session_id() -> str:
    """Generate a unique session ID."""
    return str(uuid.uuid4())


def calculate_session_timing(
    duration_hours: float, buffer_minutes: int = 10
) -> tuple[datetime, datetime | None, datetime | None]:
    """Calculate session timing details."""
    start_time = datetime.now()

    if duration_hours > 0:
        end_time = start_time + timedelta(hours=duration_hours)
        work_until = end_time - timedelta(minutes=buffer_minutes)
        return start_time, end_time, work_until

    return start_time, None, None


async def print_claude_response(
    response_iterator: AsyncIterator[Any],
    printer: Callable[[str], None] | None = None,
) -> None:
    """Print Claude's response messages as they stream in.

    Args:
        response_iterator: Async iterator from query()
        printer: Optional custom print function (defaults to click.echo)
    """
    if printer is None:
        printer = click.echo

    async for message in response_iterator:
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    printer(block.text)
