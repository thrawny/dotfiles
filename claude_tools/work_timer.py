#!/usr/bin/env python3
"""Claude Code Work Timer CLI."""

import logging
from pathlib import Path

import anyio
import asyncclick as click

from .core import run_work_session
from .duration import DurationType


@click.command()
@click.argument("task")  # Task/prompt for Claude Code
@click.option(
    "-d",
    "--duration",
    type=DurationType(),
    default="0",
    help='Duration (e.g., "2h", "90m", "1h30m", or "1.5" for hours)',
)
@click.option(
    "-b",
    "--buffer",
    type=DurationType(),
    default="10m",
    help='Buffer time before finish (e.g., "10m", "5m", or "0.167" for hours)',
)
@click.option("--cwd", type=click.Path(path_type=Path), help="Working directory")
@click.option("--debug", is_flag=True, help="Run only one iteration for debugging")
@click.option("-v", "--verbose", is_flag=True, help="Enable verbose debug logging")
@click.option(
    "-f",
    "--force",
    is_flag=True,
    default=True,
    help="Bypass permissions (default: True)",
)
@click.option(
    "-i",
    "--iterations",
    type=int,
    default=1,
    help="Number of iterations to run (default: 1)",
)
async def main(
    task: str,
    duration: float,
    buffer: float,
    cwd: Path | None,
    debug: bool,
    verbose: bool,
    force: bool,
    iterations: int,
) -> int:
    """Run Claude Code for a specified duration or number of iterations."""
    # Setup logging
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(asctime)s - %(levelname)s - %(message)s",
        datefmt="%H:%M:%S",
    )
    logger = logging.getLogger(__name__)

    if verbose:
        logger.info(f"Task: {task}")
        logger.info(f"Duration: {duration}, Iterations: {iterations}")
    else:
        click.echo(f"📋 Task: {task}")
        click.echo(f"⏰ Duration: {duration}h, Iterations: {iterations}")

    # Validate mutually exclusive options
    if iterations > 0 and duration > 0:
        click.echo("❌ Error: Iterations and duration are mutually exclusive", err=True)
        return 1

    # Convert buffer from hours to minutes for run_work_session
    buffer_minutes = int(buffer * 60)

    # Run the work session
    return await run_work_session(
        task=task,
        duration=duration,
        buffer=buffer_minutes,
        cwd=str(cwd) if cwd else None,
        debug=debug,
        force=force,
        iterations=iterations,
    )


def cli_main():
    """Entry point for the CLI command."""
    import sys

    sys.exit(anyio.run(main.main, backend="asyncio"))


if __name__ == "__main__":
    cli_main()
