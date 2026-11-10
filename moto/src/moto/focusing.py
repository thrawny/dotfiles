from __future__ import annotations

import argparse
import sys

from moto import backend, herdr_backend
from moto.common import DRIVER_ROLE, MOTO_HOME, WATCH_MOD, MotoError
from moto.driverstate import read_driver
from moto.roles import roles_dir


def cmd_pin(_: argparse.Namespace) -> int:
    """Move the driver's workspace to the top of the sidebar, if it is open."""
    herdr_backend.pin(MOTO_HOME.resolve())
    return 0


def cmd_focus(_: argparse.Namespace) -> int:
    """Focus the driver session, starting it in its home folder if none is open."""
    home = MOTO_HOME.resolve()
    if not home.is_dir():
        raise MotoError(f"moto home not found: {home}")
    herdr_backend.focus_driver(
        home, driver_env(), WATCH_MOD, read_driver().get("pane_id")
    )
    return 0


def driver_env() -> dict[str, str]:
    """The environment that starts the driver in its role.

    Until MOTO_HOME has a roles folder, the driver runs on MOTO_HOME's
    CLAUDE.md, and focus says so on each start. Once it has one, a missing
    driver role is a mistake, and focus refuses rather than start a driver
    without instructions.
    """
    path = roles_dir() / f"{DRIVER_ROLE}.md"
    if path.is_file():
        return {"MOTO_ROLE": DRIVER_ROLE}
    if roles_dir().is_dir():
        raise MotoError(f"role file missing: {path}, so the driver has no role")
    notice = f"moto: no {path}, so the driver starts without a role"
    print(notice, file=sys.stderr)
    backend.notify(notice)
    return {}
