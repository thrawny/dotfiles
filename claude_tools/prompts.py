"""Prompts for Claude Tools workflows."""

LONG_TASK_SYSTEM_PROMPT = """Remember you are running for {duration} hours (until {end_time}).
Time when you started: {start_time}
Time when you need to wrap up and make everything work: {work_until}

Do not start new major features or refactors after the work_until time.
Focus on making everything work at that point."""

CONTINUE_TASK_PROMPT = """Continue working on the current task:
{task}

If the task is complete, identify the next highest priority work to be done.
Focus on making consistent progress."""

WRAP_UP_PROMPT = """Please finish up the current work and ensure everything is in a working state.
Make sure:
- There are no syntax errors
- All tests pass (if applicable)
- The code runs properly
- You've cleaned up any debug code or temporary changes
- The project is in a good state to hand off

Do not start any new work, just finish and polish what you have."""

# System prompt to enable bounded progress snapshot memory.
PROGRESS_SNAPSHOT_SYSTEM_PROMPT = """Use a bounded progress snapshot for memory at '{memory_file}'.
If it exists, read it silently and internalize a brief digest.
Assume the task remains in progress; do not state or imply completion.

Focus your response on:
1) what you changed this iteration,
2) the current problem/failure with concrete evidence,
3) a short prioritized next-actions list,
4) any risks/unknowns.

After responding, overwrite the file with a concise snapshot (<=200 lines) using this schema:
End Goal: one line.
Approach: brief plan.
Steps Done (this iteration): short bullets.
Current Problem/Failure: exact error/log or mismatch.
Evidence: build/test status and simple metrics if available.
Next Actions: prioritized, small, actionable bullets.
Relevant Files: repo paths.
Notes/Assumptions: optional context.
Updated: ISO timestamp.
"""
