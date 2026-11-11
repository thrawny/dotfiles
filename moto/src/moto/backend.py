"""Where workers run: the Herdr TUI or herdr-core (hc), behind one interface.

Each task records its terminal: a Herdr pane id such as w3A:p5, or an hc
address such as t7. The id alone says which backend runs it, because Herdr
pane ids always hold a colon and hc addresses never do. So every call here
takes a terminal and sends the work to that terminal's backend.

Live agents come from both backends at once, keyed by terminal, in Herdr's
shape: agent, agent_status, state_change_seq, cwd, name, tab_id,
workspace_id, pane_id and terminal_title_stripped. A backend that is not
running adds none.
"""

from __future__ import annotations

import os
from types import ModuleType
from typing import Any

from moto import hc_backend, herdr_backend

HERDR = "herdr"
HC = "hc"


def kind(terminal: str) -> str:
    """The backend that runs this terminal."""
    return HERDR if ":" in terminal else HC


def module(terminal: str) -> ModuleType:
    return herdr_backend if kind(terminal) == HERDR else hc_backend


def here() -> str | None:
    """The caller's own terminal, or None outside Herdr and hc.

    A Herdr pane id wins, because a Herdr TUI that runs inside an hc
    terminal passes HC_TERMINAL_ID on to its panes.
    """
    return os.environ.get("HERDR_PANE_ID") or os.environ.get("HC_TERMINAL_ID") or None


def here_kind() -> str | None:
    """The caller's backend, or None outside Herdr and hc."""
    terminal = here()
    return kind(terminal) if terminal else None


def live_agents() -> dict[str, dict[str, Any]]:
    """Every live agent by terminal, from each backend that runs.

    Herdr runs when its socket exists, and hc when it is installed. Their
    errors still raise, so a backend that fails never passes for one whose
    panes all closed.
    """
    found: dict[str, dict[str, Any]] = {}
    if herdr_backend.herdr_up():
        found |= herdr_backend.agents()
    if hc_backend.hc_installed():
        found |= hc_backend.agents()
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
    module(terminal).name_tab(tab)


def close_tab(terminal: str, tab: str) -> None:
    """Close the terminal's tab, if it is still open."""
    module(terminal).close_tab(tab)


def close_pane(terminal: str, tab: str) -> None:
    """Close only this terminal, leaving the rest of its tab open."""
    module(terminal).close_pane(terminal, tab)


def others_in(terminal: str, tab: str, top: str) -> bool | None:
    """Whether a tab other than this one works inside the checkout at top, or
    None when the backend cannot tell."""
    return module(terminal).others_in(tab, top)


def remove_worktree(terminal: str, tab: str, path: str, repo: str, force: bool) -> None:
    """Remove a worker's worktree, and the workspace or tab on it."""
    module(terminal).remove_worktree(tab, path, repo, force)


def notify(text: str) -> None:
    """Show a notice where the user looks, if the caller's backend has one."""
    if here_kind() != HC:
        herdr_backend.notify(text)
