from __future__ import annotations

import argparse
from pathlib import Path

from moto.common import DOC_LIMITS, MOTO_DIR, MOTO_HOME, MotoError
from moto.sessions import settings_file


def doc_limits() -> dict[Path, int]:
    """Each doc with a size limit and the limit, in characters.

    DOC_LIMITS covers the generic docs beside this package. A [doc_limits]
    table in MOTO_HOME/settings.toml adds files under MOTO_HOME.
    """
    limits = {MOTO_DIR / name: limit for name, limit in DOC_LIMITS.items()}
    extra = settings_file().get("doc_limits", {})
    if not isinstance(extra, dict):
        raise MotoError("doc_limits in settings.toml must be a table")
    for name, limit in extra.items():
        if type(limit) is not int or limit <= 0:
            raise MotoError(f"doc_limits.{name} must be a positive whole number")
        limits[MOTO_HOME / name] = limit
    return limits


def over_limit(limits: dict[Path, int]) -> list[str]:
    """One warning per doc over its limit or missing."""
    warnings: list[str] = []
    for path, limit in limits.items():
        try:
            size = len(path.read_text())
        except OSError:
            warnings.append(f"{path}: cannot be read")
            continue
        if size > limit:
            warnings.append(f"{path}: {size:,} characters, over its {limit:,}")
    return warnings


def cmd_doc_sizes(args: argparse.Namespace) -> int:
    """Warn about each doc over its limit. Exits 1 only with --strict."""
    warnings = over_limit(doc_limits())
    for warning in warnings:
        print(f"warning: {warning}")
    if not warnings:
        print("Every moto doc is within its limit.")
    return 1 if warnings and args.strict else 0
