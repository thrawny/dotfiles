"""Core functionality for Claude Tools."""

import asyncio
import logging
import uuid
from datetime import datetime, timedelta
from typing import Any

from claude_code_sdk import AssistantMessage, ClaudeCodeOptions, TextBlock, query

from .prompts import (
    CONTINUE_TASK_PROMPT,
    LONG_TASK_SYSTEM_PROMPT,
    WORKFLOW_PROMPTS,
    WRAP_UP_PROMPT,
)


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


async def run_claude_query(prompt: str, options: ClaudeCodeOptions) -> bool:
    """Run a single Claude Code query and print the response."""
    logger = logging.getLogger(__name__)
    try:
        async for message in query(prompt=prompt, options=options):
            if isinstance(message, AssistantMessage):
                for block in message.content:
                    if isinstance(block, TextBlock):
                        logger.info(block.text)
        return True
    except Exception as e:
        error_str = str(e)
        logger.error(f"Error running Claude: {error_str}")

        # Check for API errors that we should retry
        if any(
            err in error_str for err in ["500", "529", "Overloaded", "api_error", "503"]
        ):
            return False

        raise e


async def run_claude_task(
    prompt: str,
    base_options: dict[str, Any],
    session_id: str,
    resume: bool = False,
    max_retries: int = 2,
    retry_delay: int = 180,
) -> bool:
    """Run a Claude task with automatic retry logic for API errors."""
    logger = logging.getLogger(__name__)

    # Create initial options
    options = ClaudeCodeOptions(**base_options)
    if resume:
        options.resume = session_id
    else:
        options.extra_args = {"session-id": session_id}

    # Try the initial request
    if await run_claude_query(prompt, options):
        return True

    # Handle API errors with retries
    for attempt in range(max_retries):
        logger.info(f"API error detected (attempt {attempt + 1}/{max_retries})")
        logger.info(
            f"Waiting {retry_delay} seconds before resuming session {session_id}..."
        )
        await asyncio.sleep(retry_delay)

        # Create resume options
        resume_options = ClaudeCodeOptions(**base_options, resume=session_id)

        if await run_claude_query("Please continue where you left off", resume_options):
            return True

    logger.error(f"Failed after {max_retries} retry attempts")
    return False


async def run_five_step_iteration(
    session_id: str,
    task_prompt: str,
    base_options: dict[str, Any],
    iteration_number: int = 1,
) -> bool:
    """Run the five-step iteration workflow."""
    logger = logging.getLogger(__name__)
    logger.info(f"--- Iteration {iteration_number} ---")
    logger.info(f"Iteration session ID: {session_id}")

    # Step 1: Coding phase
    logger.info("[Step 1/5] Doing work on task...")
    if not await run_claude_task(task_prompt, base_options, session_id):
        logger.error("Failed at coding phase")
        return False

    # Steps 2-5: Review and improvement phases
    steps = [
        ("code_review", "[Step 2/5] Running code review..."),
        ("fix_issues", "[Step 3/5] Fixing issues from code review..."),
        ("analyze_complexity", "[Step 4/5] Analyzing code complexity..."),
        ("apply_simplifications", "[Step 5/5] Applying simplification suggestions..."),
    ]

    for prompt_key, description in steps:
        logger.info(description)
        if not await run_claude_task(
            WORKFLOW_PROMPTS[prompt_key],
            base_options,
            session_id,
            resume=True,
        ):
            logger.error(
                f"Error in {prompt_key} phase, waiting 5 minutes before continuing..."
            )
            await asyncio.sleep(300)
            return False

    return True


async def run_work_session(
    task: str,
    duration: float = 0.0,
    buffer: int = 10,
    cwd: str | None = None,
    debug: bool = False,
    force: bool = True,
    iterations: int = 1,
) -> int:
    """Run a work session with the configured parameters."""
    logger = logging.getLogger(__name__)

    # Calculate timing
    start_time, end_time, work_until = calculate_session_timing(duration, buffer)

    # Generate session ID
    session_id = generate_session_id()
    logger.info(f"Session ID: {session_id}")

    # Setup base options
    base_options = {
        "permission_mode": "bypassPermissions" if force else None,
        "cwd": cwd,
    }

    # Add long task prompt if using duration mode
    if not debug and duration > 0:
        base_options["append_system_prompt"] = LONG_TASK_SYSTEM_PROMPT.format(
            duration=duration,
            start_time=start_time.strftime("%H:%M:%S"),
            end_time=end_time.strftime("%H:%M:%S") if end_time else "N/A",
            work_until=work_until.strftime("%H:%M:%S") if work_until else "N/A",
        )

    # Log session info
    if duration > 0:
        logger.info(f"Starting work session: {duration} hours")
        if work_until:
            logger.info(f"Will work until: {work_until.strftime('%H:%M:%S')}")
        if end_time:
            logger.info(f"Final wrap-up at: {end_time.strftime('%H:%M:%S')}")
    else:
        logger.info(f"Starting iteration-based session: {iterations} iterations")
    logger.info("-" * 50)

    iteration = 1

    # Main work loop
    while (work_until is not None and datetime.now() < work_until) or (
        iterations > 0 and iteration <= iterations
    ):
        remaining_time = work_until - datetime.now() if work_until else None
        remaining_iterations = iterations - iteration + 1

        if remaining_time:
            logger.info(f"Time remaining: {remaining_time}")
        else:
            logger.info(f"Iterations remaining: {remaining_iterations}")

        # Generate iteration session ID
        iteration_session_id = generate_session_id()

        # Prepare task prompt
        task_prompt = task if iteration == 1 else CONTINUE_TASK_PROMPT.format(task=task)

        # Run the iteration
        success = await run_five_step_iteration(
            session_id=iteration_session_id,
            task_prompt=task_prompt,
            base_options=base_options,
            iteration_number=iteration,
        )

        if not success:
            logger.error("Iteration failed, waiting 5 minutes before continuing...")
            await asyncio.sleep(300)
            continue

        iteration += 1

        # Break after first iteration if debug mode
        if debug:
            logger.info("[DEBUG MODE: Stopping after one iteration]")
            break

        # Small delay between iterations
        await asyncio.sleep(5)

    # Final wrap-up
    logger.info("=" * 50)
    logger.info("TIME TO WRAP UP!")
    logger.info("=" * 50)

    wrapup_session_id = generate_session_id()
    logger.info(f"Wrap-up session ID: {wrapup_session_id}")

    await run_claude_task(
        prompt=WRAP_UP_PROMPT,
        base_options=base_options,
        session_id=wrapup_session_id,
        resume=False,
    )

    logger.info("Work session completed!")
    return 0
