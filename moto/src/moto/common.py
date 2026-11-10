from __future__ import annotations

import os
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, NamedTuple

MOTO_HOME = Path(os.environ.get("MOTO_HOME") or Path.home() / "code/moto")
# A report lands a moment before the worker's turn ends. Holding it back this
# long lets the turn end first, so one wake covers both.
REPORT_SETTLE_SECONDS = 20
# Reports a task keeps for the watch, more than any worker sends between two.
REPORTS_KEPT = 20
# How long a turn end waits for the worker's transcript to catch up with Herdr,
# and for the next turn to start once the worker's background work finishes.
TURN_SETTLE_SECONDS = 10
# Background work keeps a turn end quiet this long, then the driver hears of it.
BUSY_LIMIT = 15 * 60
# Claude wraps a pasted prompt, such as a long brief, in this tag.
PASTED = re.compile(r"^\s*(<pasted_content[^>]*>\s*)?")
# The Herdr workspace for dev servers, tunnels and other long-running tabs.
BACKGROUND_WORKSPACE = "background"
# Claude's footer counts background work Herdr does not, as in "· 1 shell ·".
BACKGROUND_WORK = re.compile(
    r"· (\d+ (?:shells?|monitors?|local agents?))(?= ·|$)", re.M
)
REPORT_KINDS = ("done", "question", "blocked", "wrap", "handback", "snooze", "phase")
# Reports that make a session the user started, which no task owns, a task:
# the user handing it to the driver to finish, park or carry on.
ADOPT_KINDS = ("wrap", "snooze", "handback")
# Reports that end the task's work, so it needs no watch once the driver saw them.
FINISHED = ("done", "wrap")
# Reports from the user ending the worker on purpose, so close needs no idle pane.
ENDED_BY_USER = ("wrap", "snooze")
# A closed pane is news only once it has stayed gone this long, because the user
# may be resuming its session in a new pane, which attach then moves the task to.
PANE_GONE_GRACE = 2 * 60
# How long moto handoff waits for the new session, then for takeoff's turn to end.
HANDOFF_SESSION_WAIT = 5 * 60
HANDOFF_TAKEOFF_WAIT = 15 * 60
HANDOFF_POLL_SECONDS = 2
# A handoff marker older than this is a crashed handoff, so the watch stops absorbing.
HANDOFF_MARKER_LIFE = 30 * 60
# The handoff mod's flag that keeps the session, which moto handoff cannot wait on.
HANDOFF_STAY = "--stay"
# Herdr states of an agent that is mid-turn or waiting at a prompt.
BUSY = ("working", "blocked")
# The defaults for MOTO_HOME/settings.toml, in tokens of a worker's context.
SETTINGS = {
    # A phase report above this hands the worker off to a fresh session, and
    # below it tells the worker to carry on.
    "handoff_tokens": 100_000,
    # A turn that ends above this, without a report, gets /compact.
    "compact_tokens": 500_000,
}
# The context must grow this much after one /compact before the next.
COMPACT_GROWTH = 200_000
# The parts of a reply's usage that together are the context Claude sent.
CONTEXT_USAGE = (
    "input_tokens",
    "cache_creation_input_tokens",
    "cache_read_input_tokens",
    "output_tokens",
)
# moto list asks GitHub when a held task's PR last changed, and gives up after this.
PR_TIMEOUT = 3
PR_URL = re.compile(r"https://github\.com/[^/\s]+/[^/\s]+/pull/\d+")
CLAUDE_HOME = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
# This package's own folder, and the moto folder in dotfiles that holds it.
PACKAGE = Path(__file__).resolve().parent
MOTO_DIR = PACKAGE.parents[1]
# The command that runs this moto again, for processes it starts.
SELF = [sys.executable, "-m", "moto"]
# The generic moto skills, next to this package in dotfiles.
CORE_SKILLS = MOTO_DIR / "skills"
# The Claude Code mod that watches workers from inside the driver session.
WATCH_MOD = MOTO_DIR / "claude/mods/moto-watch"

# Marks every prompt the driver sends, so a worker can tell it from the user's own typing.
# A worker's prompts to the workers it started carry its own name instead.
DRIVER_TAG = "[driver]"
# Reports the watch carries from a child to its parent, and the tag each starts
# with there, as in "[abc-2 done] PR ready".
CHILD_KINDS = ("done", "question", "blocked", "phase")
CHILD_REPORT = re.compile(rf"\[\S+ (?:{'|'.join(CHILD_KINDS)})\] ")
# Slash commands moto itself submits to a worker's pane as typed, so they are not the user's.
MOTO_COMMANDS = ("/handoff", "/takeoff", "/compact")
# The watch looks for the user's latest prompt in this much of a transcript's end.
USER_PROMPT_TAIL = 2 * 1024 * 1024
# Herdr states of a parent that can take a child's report: its turn has ended.
TURN_OVER = ("idle", "done")
REPORT_RULES = """\
When a turn ends with the task finished, with a question only the user can \
answer, or with the work blocked, make your last action \
`moto report done|question|blocked "<one line>"`. \
Put the PR URL in a done line when there is one. Never merge a PR on your \
own, only when the user tells you to, in your brief or in your pane. After you \
open one, follow your instructions for what comes next, such as watching the PR."""
SPAWN_RULES = """\
To hand work off to a separate task, such as research that splits into \
implementation tasks, start it with `moto spawn --to-driver`, so the driver \
watches it. Start a helper you supervise yourself, such as a test worker, with \
plain `moto spawn`. Its done, question and blocked reports arrive in your \
pane once your turn ends, tagged with its name and the kind, as in \
`[helper done]`; answer a question with `moto tell`."""
# Taught wherever a worker learns the driver is not watching it.
PASS_ON_RULE = """\
When the user asks you to pass something to the driver, run \
`moto report --to-driver done|question|blocked "<one line>"`. The driver gets \
it even while it does not watch you, and a hold stays in place."""
BRIEF_FOOTER = f"""\
A driver session started you and tracks this task for the user. {REPORT_RULES}

Every message from the driver starts with {DRIVER_TAG}, as this one does. A \
message without it is from the user, typing in this pane. Answer the user here, \
and when the user and the driver disagree, follow the user. Still report to the \
driver when the task finishes, gets stuck or needs a decision. {PASS_ON_RULE}

{SPAWN_RULES}"""
CHILD_FOOTER = f"""\
Another worker, {{parent}}, started you and takes your reports, which moto \
delivers to its pane. A driver session tracks {{parent}} for the user. \
{REPORT_RULES}

Every message from {{parent}} starts with [{{parent}}], as this one does. A \
message that starts with {DRIVER_TAG} is from the driver, and a message with \
neither tag is from the user, typing in this pane. Answer the user here. When \
they disagree, follow the user first, then the driver, then {{parent}}. \
{PASS_ON_RULE}

{SPAWN_RULES}"""


UNTRACKED = (
    "No driver session is tracking this one, so there is nothing to report to. "
    + "Tell the user directly."
)
# What a fork may run: commands that only read, and hooks that skip forks.
FORK_SAFE = ("list", "log", "focus", "pin", "link", "role")
ROLE_NAME = re.compile(r"[a-z][a-z0-9_-]{0,31}")
# The role moto focus starts the driver in; spawn refuses it to workers.
DRIVER_ROLE = "driver"


# Scheduled jobs. The gate's exit codes are shepherd's, deliberately: a broken
# gate runs the job anyway, because a schedule that dies quietly is worse.
GATE_TIMEOUT = 120
GATE_SKIP = 75
JOB_TICK_SECONDS = 60
# A tick takes seconds; a loop silent for longer than this has stopped.
JOB_BEAT_STALE_SECONDS = 180
WEEKDAYS = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}
JOB_FIELDS = {
    "name",
    "at",
    "days",
    "gate",
    "deliver",
    "brief",
    "enabled",
    "stale_after",
    "repo",
    "worktree",
    "base",
    "agent",
    "title",
}
# Marks a scheduled job's prompt, so the driver and a worker can tell it from
# the driver's own messages and from the user's typing. It outranks neither.
JOB_TAG = "[job]"
JOB_FOOTER = f"""\
A scheduled moto job started you, and a driver session tracks this task for the \
user. {REPORT_RULES}

Messages from the driver start with {DRIVER_TAG}. A message without it is from \
the user, typing in this pane. Answer the user here, and when the user and the \
driver disagree, follow the user. A job is a trigger, not an authority: follow \
exactly the rules a worker the driver started follows, the user's away rules \
included."""

EVENTS_VERSION = 1


class MotoError(Exception):
    pass


class Step(NamedTuple):
    """What the watch does to a worker after its update: tell it to carry on,
    hand it off to a fresh session, or compact its context."""

    agent: str
    action: str
    text: str


class Delivery(NamedTuple):
    """A child's reports on their way into its parent's pane."""

    child: str
    parent: str
    text: str


# Events recorded during the current tasks_for_update, appended when it commits.
pending_events: list[dict[str, Any]] = []


def state_dir() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return Path(base) / "moto"


def run(
    args: list[str],
    cwd: str | Path | None = None,
    timeout: int = 30,
    stdin: str | None = None,
) -> str:
    try:
        result = subprocess.run(
            args,
            cwd=cwd,
            input=stdin,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError as error:
        raise MotoError(f"Required executable not found: {args[0]}") from error
    if result.returncode:
        raise MotoError(
            result.stderr.strip() or result.stdout.strip() or f"{args[0]} failed"
        )
    return result.stdout


def age(seconds: float) -> str:
    seconds = max(0, int(seconds))
    for unit, size in (("d", 86400), ("h", 3600), ("m", 60)):
        if seconds >= size:
            return f"{seconds // size}{unit}"
    return f"{seconds}s"


def timestamp(text: Any) -> float | None:
    try:
        return datetime.fromisoformat(text).timestamp()
    except (TypeError, ValueError):
        return None


# The worker's Claude model and effort, which spawn-session passes to claude.
MODEL_FLAGS = ("model", "effort")
EFFORTS = ("low", "medium", "high", "xhigh", "max")
# What moto spawn starts a worker on when its flags leave one out.
SPAWN_DEFAULTS = {"model": "opus", "effort": "medium"}
# Set in a worker's tab, so a worker in MOTO_HOME never passes for the driver.
WORKER_ENV = "MOTO_WORKER"


def exit_on_signal(number: int, _frame: object) -> None:
    sys.exit(128 + number)


def clock(ts: float) -> str:
    return time.strftime("%H:%M", time.localtime(ts))
