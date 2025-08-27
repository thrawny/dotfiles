#!/usr/bin/env python3
"""Simple loop runner for Claude Code - runs a task repeatedly for a specified duration."""

import logging
import time
from datetime import datetime, timedelta
from pathlib import Path
import asyncclick as click
from claude_code_sdk import ClaudeCodeOptions, query

from .duration import DurationType


@click.command()
@click.argument("task")
@click.option(
    "-d",
    "--duration",
    type=DurationType,
    default="30m",
    help='Duration (e.g., "1h", "30m", "1h30m", "90m", or "0.5" for hours)',
)
@click.option(
    "-w",
    "--wait",
    type=DurationType,
    default="30s",
    help='Wait time between iterations (e.g., "30s", "1m", "5m", or "0.0083" for hours)',
)
@click.option(
    "--cwd", type=click.Path(exists=True, path_type=Path), help="Working directory"
)
@click.option("-v", "--verbose", is_flag=True, help="Enable verbose debug logging")
async def cli(
    task: str,
    duration: float,
    wait: float,
    cwd: Path | None,
    verbose: bool,
) -> None:
    """Run Claude Code in a simple loop for a specified duration.

    This is a simpler alternative to claude-work-timer that just runs
    the task repeatedly without the review/simplify workflow.

    Example:
        claude-loop "fix all the type errors" -d 1.0
    """
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )

    end_time = datetime.now() + timedelta(hours=duration)
    iteration = 0

    click.echo(f"🔄 Starting simple loop for {duration} hours")
    click.echo(f"📋 Task: {task}")
    click.echo(f"⏰ Will run until: {end_time.strftime('%H:%M:%S')}")
    wait_seconds = int(wait * 3600)  # Convert hours to seconds
    click.echo(f"⏸️  Wait time between iterations: {wait_seconds}s")
    click.echo()

    options = ClaudeCodeOptions(cwd=str(cwd) if cwd else None)

    while datetime.now() < end_time:
        iteration += 1
        remaining = (end_time - datetime.now()).total_seconds()

        if remaining <= 0:
            break

        click.echo(f"🚀 Iteration {iteration} - {remaining / 60:.1f} minutes remaining")

        try:
            async for _ in query(prompt=task, options=options):
                pass  # Just consume the response
            click.echo(f"✅ Iteration {iteration} complete")
        except KeyboardInterrupt:
            click.echo("\n⏹️  Stopped by user")
            break
        except Exception as e:
            click.echo(f"❌ Error in iteration {iteration}: {e}")

        # Wait between iterations if not the last one
        if datetime.now() + timedelta(seconds=wait_seconds) < end_time:
            click.echo(f"⏳ Waiting {wait_seconds} seconds before next iteration...")
            time.sleep(wait_seconds)
        else:
            break

    click.echo(f"\n✨ Completed {iteration} iterations in {duration} hours")


def cli_main():
    """Synchronous entry point for the CLI."""
    import asyncio

    asyncio.run(cli())


if __name__ == "__main__":
    cli_main()
