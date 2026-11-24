"""Where workers run: the Herdr TUI, herdr-core (hc) or Rex, behind one interface.

Each task records its terminal: a Herdr pane id such as w3A:p5, an hc address
such as t7, or a Rex block id such as block:01a2.... The id alone says which
backend runs it: Rex ids start with block:, other Herdr pane ids hold a colon,
and hc addresses never do. So every call here takes a terminal and sends the
work to that terminal's backend.

Live agents come from every backend at once, keyed by terminal, in Herdr's
shape: agent, agent_status, state_change_seq, cwd, name, tab_id,
workspace_id, pane_id and terminal_title_stripped. A backend that is not
running adds none.
"""

from __future__ import annotations

import os
from types import ModuleType
from typing import Any

from moto import hc_backend, herdr_backend, rex_backend

HERDR = "herdr"
HC = "hc"
REX = "rex"
MODULES = {HERDR: herdr_backend, HC: hc_backend, REX: rex_backend}


def kind(terminal: str) -> str:
    """The backend that runs this terminal."""
    if terminal.startswith("block:"):
        return REX
    return HERDR if ":" in terminal else HC


def module(terminal: str) -> ModuleType:
    return MODULES[kind(terminal)]


def here() -> str | None:
    """The caller's own terminal, or None outside Herdr, hc and Rex.

    The innermost one wins: a Herdr TUI passes the REX_BLOCK or
    HC_TERMINAL_ID of the terminal it runs in on to its panes.
    """
    return (
        os.environ.get("HERDR_PANE_ID")
        or os.environ.get("REX_BLOCK")
        or os.environ.get("HC_TERMINAL_ID")
        or None
    )


def here_kind() -> str | None:
    """The caller's backend, or None outside Herdr, hc and Rex."""
    terminal = here()
    return kind(terminal) if terminal else None


def live_agents() -> dict[str, dict[str, Any]]:
    """Every live agent by terminal, from each backend that runs.

    Herdr runs when its socket exists, hc when it is installed, and Rex when
    it is installed and its server answers. Their errors still raise, so a
    backend that fails never passes for one whose panes all closed.
    """
    found: dict[str, dict[str, Any]] = {}
    if herdr_backend.herdr_up():
        found |= herdr_backend.agents()
    if hc_backend.hc_installed():
        found |= hc_backend.agents()
    if rex_backend.rex_installed():
        found |= rex_backend.agents()
    return found


def prompt(name: str, terminal: str, text: str) -> None:
    """Type text into a task's agent and submit it."""
    module(terminal).prompt(name, terminal, text)


def screen(terminal: str) -> str:
    """What the terminal shows now."""
    return module(terminal).screen(terminal)


def rename(terminal: str, name: str | None) -> None:
    """Give the agent in this terminal a name, or clear it with None."""
    module(terminal).rename(terminal, name)


def name_tab(terminal: str, tab: str) -> None:
    """Label the terminal's tab claude, so it tells a Claude session from a
    tab of servers. The agent name, not the label, carries the task."""
    module(terminal).name_tab(terminal, tab)


def close_tab(terminal: str, tab: str) -> None:
    """Close the terminal's tab, if it is still open."""
    module(terminal).close_tab(terminal, tab)


def close_pane(terminal: str, tab: str) -> None:
    """Close only this terminal, leaving the rest of its tab open."""
    module(terminal).close_pane(terminal, tab)


def others_in(terminal: str, tab: str, top: str) -> bool | None:
    """Whether a tab other than this one works inside the checkout at top, or
    None when the backend cannot tell."""
    return module(terminal).others_in(tab, top)


def remove_worktree(terminal: str, tab: str, path: str, repo: str, force: bool) -> None:
    """Remove a worker's worktree, and the workspace or tab on it."""
    module(terminal).remove_worktree(terminal, tab, path, repo, force)


def clear_held_mark(terminal: str) -> None:
    """Clear the held mark moto hold once put on this terminal."""
    module(terminal).clear_held_mark(terminal)


def notify(text: str) -> None:
    """Show a notice where the user looks, if the caller's backend has one."""
    # Only Herdr has notices; Rex shows its own for agents that need the user.
    if here_kind() not in (HC, REX):
        herdr_backend.notify(text)
