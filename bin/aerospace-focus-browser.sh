#!/usr/bin/env bash
set -euo pipefail

# Priority: Arc -> Zen
window_id=$(aerospace list-windows --monitor all --format "%{app-bundle-id}:%{window-id}" \
  | grep -E "^(company.thebrowser.Browser|app.zen-browser.zen):" \
  | head -n1 \
  | cut -d: -f2)

[[ -n "$window_id" ]] && aerospace focus --window-id "$window_id" || open https://
