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

WORKFLOW_PROMPTS = {
    "code_review": """Use the code-reviewer agent to review all the code you've written so far in this session.
The agent should check for bugs, security issues, and code quality problems.
Wait for the agent to complete its review.""",
    "fix_issues": """Fix ALL issues identified by the code-reviewer agent.
Make sure to address every concern raised.
After fixing, verify the code still works correctly.""",
    "analyze_complexity": """Use the complexity-reducer agent to analyze the code for unnecessary complexity.
The agent should identify opportunities to simplify and improve readability.
Wait for the agent to complete its analysis.""",
    "apply_simplifications": """Apply the simplification suggestions from the complexity-reducer agent.
Focus on making the code cleaner and easier to understand.
After simplifying, ensure everything still works.""",
}
