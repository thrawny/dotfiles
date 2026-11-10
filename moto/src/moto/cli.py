from __future__ import annotations

import argparse
import subprocess
import sys

import moto
from moto.afk import cmd_afk, cmd_back, cmd_log, cmd_log_action
from moto.attaching import cmd_attach
from moto.closing import cmd_close, cmd_drop, cmd_hold, cmd_resume
from moto.common import (
    EFFORTS,
    FORK_SAFE,
    JOB_TICK_SECONDS,
    REPORT_KINDS,
    SPAWN_DEFAULTS,
    MotoError,
    herdr,
)
from moto.focusing import cmd_focus, cmd_pin
from moto.listing import cmd_list
from moto.reporting import cmd_ask, cmd_handoff, cmd_report, cmd_settle, cmd_tell
from moto.roles import cmd_link, cmd_role
from moto.scheduler import cmd_job_list, cmd_job_loop, cmd_job_run, cmd_job_tick
from moto.snoozing import cmd_snooze, cmd_wake
from moto.spawning import cmd_spawn
from moto.store import forked
from moto.watching import cmd_watch
from moto.whenstore import (
    UNTIL_PR_HELP,
    WHEN_ERROR_LIMIT,
    WHEN_EVERY,
    WHEN_EXPIRES,
    cmd_job_rm,
    cmd_pr_check,
    cmd_when,
)


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(
        description=moto.__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    commands = root.add_subparsers(dest="command", required=True)

    spawn = commands.add_parser("spawn", help="Start a worker; brief on stdin")
    spawn.add_argument(
        "--repo",
        help="Repo name under ~/code or a path; with --role, a folder of MOTO_HOME"
        + " (default: MOTO_HOME itself)",
    )
    spawn.add_argument(
        "--role",
        help="For a session that works inside MOTO_HOME: start it with MOTO_ROLE"
        + " set, so it loads MOTO_HOME/roles/ROLE.md; no --worktree or --pane",
    )
    spawn.add_argument("--worktree", metavar="BRANCH", help="Work in a linked worktree")
    spawn.add_argument("--base", help="Base ref for a new worktree")
    spawn.add_argument("--name", help="Herdr agent name")
    spawn.add_argument(
        "--title",
        required=True,
        help="Claude session name: up to three lowercase words, as in 'ABC-123 summary'",
    )
    spawn.add_argument(
        "--resume",
        metavar="SESSION_ID",
        help="Resume an earlier Claude session as the worker",
    )
    spawn.add_argument(
        "--model",
        help="Claude model for the worker: an alias such as sonnet, or a full"
        + f" name; default: {SPAWN_DEFAULTS['model']}",
    )
    spawn.add_argument(
        "--effort",
        choices=EFFORTS,
        help=f"Claude effort level; default: {SPAWN_DEFAULTS['effort']}",
    )
    spawn.add_argument(
        "--pane",
        metavar="PANE_ID",
        help="Adopt this pane instead of opening one, for a caller that built"
        + " the workspace itself, such as pr-review --worktree",
    )
    spawn.add_argument(
        "--to-driver",
        action="store_true",
        help="From a worker: hand the task to the driver, which watches it and"
        + " takes its reports, instead of supervising it yourself",
    )
    spawn.add_argument("--json", action="store_true", help="Print the new task as JSON")
    spawn.set_defaults(handler=cmd_spawn)

    tell = commands.add_parser(
        "tell",
        help="Prompt a worker, tagged [driver] or with the worker that started it",
    )
    tell.add_argument("agent")
    tell.add_argument("text", nargs="*", help="The message; default: stdin")
    tell.set_defaults(handler=cmd_tell)

    handoff = commands.add_parser(
        "handoff",
        help="Hand an idle worker off to a fresh session in its pane;"
        + " the brief for the new session is optional, on stdin",
    )
    handoff.add_argument("agent")
    handoff.add_argument(
        "goal", nargs="*", help="What the new session should do; default: none"
    )
    handoff.add_argument("--from-watch", action="store_true", help=argparse.SUPPRESS)
    handoff.set_defaults(handler=cmd_handoff)

    ask = commands.add_parser(
        "ask", help="Show the driver's question to the user in the sidebar"
    )
    ask.add_argument("text", nargs="*")
    ask.add_argument("--clear", action="store_true", help="Remove the question")
    ask.set_defaults(handler=cmd_ask)

    listing = commands.add_parser(
        "list", help="Workers with live state, PR and last report"
    )
    listing.add_argument("--json", action="store_true")
    listing.set_defaults(handler=cmd_list)

    report = commands.add_parser(
        "report",
        help="Run by a worker to report to the driver; wrap, handback and"
        + " snooze also end a hold, and phase asks for a fresh session",
    )
    report.add_argument("kind", choices=REPORT_KINDS)
    report.add_argument("text", nargs="+")
    report.add_argument("--agent", help="Task name; default: the task in this pane")
    report.add_argument(
        "--to-driver",
        action="store_true",
        help="Reach the driver even from a held task or one another worker"
        + " started, without ending a hold; for when the user asks",
    )
    report.set_defaults(handler=cmd_report)

    settle = commands.add_parser(
        "settle",
        help="Run by the driver to replace a task's settled question; not news",
    )
    settle.add_argument("agent")
    settle.add_argument("text", nargs="+", help="What settled it")
    settle.set_defaults(handler=cmd_settle)

    watch = commands.add_parser(
        "watch", help="One pass, as JSON, of what needs the driver"
    )
    watch.set_defaults(handler=cmd_watch)

    close = commands.add_parser("close", help="Remove a worker's tab and worktree")
    close.add_argument("agent")
    close.add_argument(
        "--force",
        action="store_true",
        help="Remove even with unsaved work, a busy pane or the user's new prompts",
    )
    close.set_defaults(handler=cmd_close)

    hold = commands.add_parser(
        "hold",
        help="Keep a task but stop watching it; the watch also does this when the"
        + " user types in the worker's pane",
    )
    hold.add_argument("agent")
    hold.set_defaults(handler=cmd_hold)

    resume_ = commands.add_parser(
        "resume", help="Watch a held task again; a snoozed one needs wake"
    )
    resume_.add_argument("agent")
    resume_.set_defaults(handler=cmd_resume)

    attach_ = commands.add_parser(
        "attach",
        help="Move a task to the pane its Claude session was resumed in",
    )
    attach_.add_argument("agent", nargs="?")
    attach_.add_argument("--pane", help="Herdr pane id; default: this pane")
    attach_.add_argument(
        "--hook",
        action="store_true",
        help="Claude's SessionStart hook: record this pane's session, or attach"
        + " the task that ran it; silent, and always exits 0",
    )
    attach_.set_defaults(handler=cmd_attach)

    snooze = commands.add_parser(
        "snooze",
        help="Park a blocked task: save its Claude session, remove its worktree"
        + " (keeping the branch) and close its workspace",
    )
    snooze.add_argument("agent")
    snooze.add_argument("reason", nargs="+", help="Why it waits, shown in moto list")
    snooze.add_argument(
        "--until-check",
        metavar="COMMAND",
        help="Also add a moto when check that wakes the task once COMMAND exits 0",
    )
    snooze.add_argument(
        "--until-pr",
        metavar="PR",
        help="Also add a moto when check on a pull request, given as a URL or"
        + " owner/repo#N, instead of a hand-written --until-check. "
        + UNTIL_PR_HELP,
    )
    add_when_timing(snooze)
    snooze.set_defaults(handler=cmd_snooze)

    pr_check = commands.add_parser(
        "pr-check",
        help=argparse.SUPPRESS,
        description="The check --until-pr stores: exit 0 and print why when the PR"
        + " needs its task, else exit 1 quietly.",
    )
    pr_check.add_argument("pr", metavar="PR")
    pr_check.add_argument("--reviews", type=int, required=True)
    pr_check.add_argument("--comments", type=int, required=True)
    pr_check.set_defaults(handler=cmd_pr_check)

    when = commands.add_parser(
        "when",
        help="Tell the driver, or wake a task, once a shell command exits 0;"
        + " kept in moto's state folder, not MOTO_HOME",
        description="Run COMMAND every so often from the job loop. Exit 0 passes:"
        + " the brief and the tail of COMMAND's stdout go to the driver, or to the"
        + " --wake task, and the check is gone. Any other exit means not yet, and"
        + " should be quiet: a non-zero exit with stderr, 126, 127 or a timeout is"
        + f" an error, and {WHEN_ERROR_LIMIT} errors in a row tell the driver."
        + " moto when runs COMMAND once first, from the current folder, and later"
        + " runs use that folder too.",
    )
    when.add_argument("--check", metavar="COMMAND", help="Shell command to run")
    when.add_argument(
        "--until-pr",
        metavar="PR",
        help=UNTIL_PR_HELP + "; use it in place of --check",
    )
    when.add_argument(
        "--wake",
        metavar="TASK",
        help="Prompt this task with the brief, waking it first if it is snoozed;"
        + " default: the driver",
    )
    when.add_argument(
        "--name", help="Name in moto job list; default: from --wake or the brief"
    )
    add_when_timing(when)
    when.add_argument("text", nargs="*", help="The brief; default: stdin")
    when.set_defaults(handler=cmd_when)

    wake = commands.add_parser(
        "wake",
        help="Bring a snoozed task back: restore its worktree, resume its session",
    )
    wake.add_argument("agent")
    wake.add_argument("text", nargs="*", help="What changed, sent as with tell")
    wake.set_defaults(handler=cmd_wake)

    drop = commands.add_parser("drop", help="Stop tracking a worker, leaving it open")
    drop.add_argument("agent")
    drop.set_defaults(handler=cmd_drop)

    log = commands.add_parser(
        "log", help="Print events.jsonl, the append-only history of every task"
    )
    log.add_argument("agent", nargs="?", help="Only this task's events")
    log.set_defaults(handler=cmd_log)

    afk = commands.add_parser(
        "afk",
        help="Record that the user is away, with their note word for word;"
        + " new words replace the note",
    )
    afk.add_argument("text", nargs="*", help="The user's note; may be empty")
    afk.set_defaults(handler=cmd_afk)

    back = commands.add_parser(
        "back", help="End away mode and print what happened while the user was away"
    )
    back.set_defaults(handler=cmd_back)

    log_action = commands.add_parser(
        "log-action", help="Log something the driver did, for the return brief"
    )
    log_action.add_argument("text", nargs="+")
    log_action.add_argument("--agent", help="The task it concerns; default: driver")
    log_action.set_defaults(handler=cmd_log_action)

    role = commands.add_parser("role", help="Name this session's moto role")
    role.add_argument(
        "--hook",
        action="store_true",
        help="Claude's SessionStart hook: hand the session its role file as"
        + " context; silent for a session without a role",
    )
    role.set_defaults(handler=cmd_role)

    focus = commands.add_parser("focus", help="Jump to the driver session")
    focus.set_defaults(handler=cmd_focus)

    pin = commands.add_parser("pin", help="Move the driver's workspace to the top")
    pin.set_defaults(handler=cmd_pin)

    link = commands.add_parser(
        "link", help="Symlink the moto skills into ~/.claude/skills"
    )
    link.set_defaults(handler=cmd_link)

    job = commands.add_parser("job", help="Scheduled jobs: work that starts on a clock")
    job_commands = job.add_subparsers(dest="job_command", required=True)
    job_loop = job_commands.add_parser(
        "loop", help="The scheduler; ticks until stopped"
    )
    job_loop.add_argument(
        "--every",
        type=int,
        default=JOB_TICK_SECONDS,
        metavar="SECONDS",
        help="Seconds between ticks (default: %(default)s)",
    )
    job_loop.set_defaults(handler=cmd_job_loop)
    job_tick = job_commands.add_parser("tick", help="One pass: run everything due")
    job_tick.set_defaults(handler=cmd_job_tick)
    job_run = job_commands.add_parser(
        "run", help="Run a job or check now, whatever its schedule says"
    )
    job_run.add_argument("name")
    job_run.set_defaults(handler=cmd_job_run)
    job_list = job_commands.add_parser(
        "list", help="Jobs and checks with next run and last outcome"
    )
    job_list.add_argument("--json", action="store_true")
    job_list.set_defaults(handler=cmd_job_list)
    job_rm = job_commands.add_parser("rm", help="Cancel a moto when check")
    job_rm.add_argument("name")
    job_rm.set_defaults(handler=cmd_job_rm)
    return root


def add_when_timing(command: argparse.ArgumentParser) -> None:
    command.add_argument(
        "--every",
        default=WHEN_EVERY,
        metavar="DURATION",
        help="How often the check runs, as in 10m or 1h (default: %(default)s)",
    )
    command.add_argument(
        "--expires",
        default=WHEN_EXPIRES,
        metavar="DURATION",
        help="When the check gives up and tells the driver (default: %(default)s)",
    )


def main() -> int:
    args = parser().parse_args()
    try:
        if (
            forked()
            and args.command not in FORK_SAFE
            and not getattr(args, "hook", False)
        ):
            raise MotoError(
                "This session is a fork, neither the driver nor a moto worker, so it"
                + f" cannot run moto {args.command}. Answer the user in this pane."
            )
        return args.handler(args)
    except subprocess.TimeoutExpired as error:
        print(
            f"moto: {error.cmd[0]} timed out; inspect Herdr before retrying",
            file=sys.stderr,
        )
    except (MotoError, OSError) as error:
        print(f"moto: {error}", file=sys.stderr)
        if args.command == "focus":
            try:
                herdr("notification", "show", f"moto: {error}", "--sound", "none")
            except (MotoError, OSError, subprocess.TimeoutExpired):
                pass
    return 1
