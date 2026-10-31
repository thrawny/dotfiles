#!/usr/bin/env python3
"""Apply the canonical palette to the native Herdr app."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
palette = json.loads((root / "nix/themes/monokai.json").read_text())
s = palette["semantic"]
terminal = palette["terminal"]
folder = Path.home() / ".config/herdr-app"
(folder / "themes").mkdir(parents=True, exist_ok=True)
theme = {
    "background": terminal["background"],
    "foreground": terminal["foreground"],
    "selection": terminal["selection"],
    "cursor": s["foreground"],
    "ansi": terminal["normal"] + terminal["bright"],
    "colors": {
        "canvas": s["background"], "chrome": s["background"],
        "surface": s["surface"], "popover": s["surface"],
        "raised": palette["applications"]["herdr"]["surface"],
        "hover": s["selection"], "selected": s["selection"],
        "border": s["border"], "input": s["border"],
        "muted": s["muted"], "dim": s["dim"],
        "accent": s["accent"], "accent_foreground": s["background"],
        "working": palette["syntax"]["type"],
        "blocked": palette["syntax"]["function"],
        "done": s["success"], "idle": s["muted"], "unknown": s["muted"],
    },
}
(folder / "themes/monokai.json").write_text(json.dumps(theme, indent=2) + "\n")
settings_file = folder / "settings.json"
settings = json.loads(settings_file.read_text()) if settings_file.exists() else {}
settings.update(theme="monokai", appearance="dark")
settings_file.write_text(json.dumps(settings, indent=2) + "\n")
print("Applied Monokai to", folder)
