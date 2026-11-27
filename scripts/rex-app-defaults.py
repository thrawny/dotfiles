#!/usr/bin/env python3
"""Write the Rex app's look into its macOS defaults.

Usage: rex-app-defaults.py LOOK_JSON

LOOK_JSON comes from nix/home/shared/rex.nix. It holds the theme's name and
Ghostty's colors, and the app settings to write, each as a key and
{type: value}, where type is a `defaults write` type such as string or float.

The theme goes into the app's custom themes, as the app's own Ghostty import
stores it, and becomes the dark theme. Only the theme with this name is
replaced; the app's other custom themes stay. The app reads its defaults when
it starts, so a running app shows the change after a restart.
"""

import json
import plistlib
import subprocess
import sys
import time
import uuid

DOMAIN = "com.superlogical.rex"
THEMES_KEY = "Workspace.customThemes"
# Foundation dates count seconds from 2001-01-01, not from 1970.
APPLE_EPOCH = 978307200


def srgb(hex_color: str) -> dict[str, object]:
    value = hex_color.lstrip("#")
    red, green, blue = (int(value[i : i + 2], 16) / 255 for i in (0, 2, 4))
    return {"colorSpace": "srgb", "red": red, "green": green, "blue": blue, "alpha": 1}


def xterm_color(index: int) -> tuple[float, float, float]:
    """xterm's colors 16 to 255: a 6x6x6 cube, then 24 grays."""
    if index < 232:
        cube = index - 16
        levels = [
            0 if c == 0 else 55 + 40 * c for c in (cube // 36, cube // 6 % 6, cube % 6)
        ]
        return tuple(level / 255 for level in levels)  # type: ignore[return-value]
    gray = (8 + 10 * (index - 232)) / 255
    return gray, gray, gray


def palette(colors: dict[str, str], ansi: list[str]) -> dict[str, object]:
    base = {}
    for index in range(16, 256):
        red, green, blue = xterm_color(index)
        base[str(index)] = {
            "colorSpace": "srgb",
            "red": red,
            "green": green,
            "blue": blue,
            "alpha": 1,
        }
    return {
        "background": srgb(colors["background"]),
        "foreground": srgb(colors["foreground"]),
        "cursor": srgb(colors["cursor"]),
        "cursorText": srgb(colors["cursorText"]),
        "selectionBackground": srgb(colors["selectionBackground"]),
        "selectionForeground": srgb(colors["selectionForeground"]),
        "ansi": [srgb(color) for color in ansi],
        "paletteBase": base,
        "paletteGenerate": False,
        "paletteHarmonious": False,
        "paletteOverrides": {},
    }


def current_themes() -> list[dict[str, object]]:
    """The app's custom themes, or none before the app first saved any."""
    result = subprocess.run(
        ["defaults", "export", DOMAIN, "-"], capture_output=True, check=False
    )
    if result.returncode:
        return []
    raw = plistlib.loads(result.stdout).get(THEMES_KEY)
    if not raw:
        return []
    themes = json.loads(raw)
    return themes if isinstance(themes, list) else []


def write(key: str, kind: str, value: object) -> None:
    text = ("true" if value else "false") if kind == "bool" else str(value)
    subprocess.run(["defaults", "write", DOMAIN, key, f"-{kind}", text], check=True)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    with open(sys.argv[1], encoding="utf-8") as file:
        look = json.load(file)
    name = look["name"]
    themes = current_themes()
    mine = next((t for t in themes if t.get("name") == name), None)
    theme = {
        # The app's own ids are custom-<UUID>; a stable one keeps the selection.
        "id": (mine or {}).get("id")
        or f"custom-{str(uuid.uuid5(uuid.NAMESPACE_URL, f'dotfiles:{name}')).upper()}",
        "name": name,
        "appearance": "dark",
        "createdAt": (mine or {}).get("createdAt") or time.time() - APPLE_EPOCH,
        "source": {"ghosttyFile": {"fileName": name}},
        "palette": palette(look["colors"], look["ansi"]),
    }
    themes = [t for t in themes if t is not mine] + [theme]
    encoded = json.dumps(themes, separators=(",", ":")).encode()
    write(THEMES_KEY, "data", encoded.hex())
    write("Workspace.darkThemeID", "string", theme["id"])
    for key, typed in look["settings"].items():
        ((kind, value),) = typed.items()
        write(key, kind, value)
    return 0


if __name__ == "__main__":
    sys.exit(main())
