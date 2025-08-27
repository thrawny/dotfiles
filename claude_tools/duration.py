"""Duration parsing utilities for Claude Tools."""

import re
from typing import Any

import asyncclick as click


def parse_duration(value: str | float | int) -> float:
    """Parse duration string or number to hours as float.

    Supports formats like:
    - Float/int: 1.5 → 1.5 hours
    - String: "1h30m" → 1.5 hours
    - String: "90m" → 1.5 hours
    - String: "2d" → 48 hours
    - String: "1h30m45s" → 1.5125 hours

    Units:
    - d/days: days
    - h/hours: hours
    - m/min/minutes: minutes
    - s/sec/seconds: seconds

    Args:
        value: Duration as string or number

    Returns:
        Duration in hours as float

    Raises:
        ValueError: If format is invalid
    """
    # Handle numeric input (backward compatibility)
    if isinstance(value, (int, float)):
        return float(value)

    # String handling from this point

    value = value.strip()

    # Try to parse as plain number
    try:
        return float(value)
    except ValueError:
        pass

    # Parse duration string like "1h30m"
    # Pattern matches: number (with optional decimal) followed by unit
    pattern = r"(\d+(?:\.\d+)?)\s*([dhms])"
    matches = re.findall(pattern, value.lower())

    if not matches:
        raise ValueError(f"Invalid duration format: {value}")

    total_hours = 0.0
    for amount_str, unit in matches:
        amount = float(amount_str)

        if unit == "d":
            total_hours += amount * 24
        elif unit == "h":
            total_hours += amount
        elif unit == "m":
            total_hours += amount / 60
        elif unit == "s":
            total_hours += amount / 3600

    return total_hours


class DurationType(click.ParamType):
    """Click parameter type for duration strings."""

    name: str = "duration"

    def convert(self, value: Any, param: Any, ctx: Any) -> float | None:
        """Convert duration string to hours as float."""
        if value is None:
            return None

        try:
            return parse_duration(value)
        except ValueError as e:
            self.fail(
                f'{str(e)}. Valid formats: "1h", "30m", "1h30m", "90m", "2d", or numeric hours like "1.5"',
                param,
                ctx,
            )

    def get_metavar(self, param: Any, ctx: Any = None) -> str:
        """Return metavar for help text."""
        return "DURATION"


# Singleton instance for use in decorators
DURATION = DurationType()
