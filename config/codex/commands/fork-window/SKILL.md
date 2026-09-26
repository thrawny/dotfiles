---
name: fork-window
description: Fork this conversation into a Herdr tab or Hyprland window.
---

Run `fork-window codex` once in the current working directory. The launcher uses `CODEX_THREAD_ID` from the tool environment to identify this conversation exactly.

It opens a separate session sharing the checkout and sends the fork a notice to wait for new instructions. The original session stays open.

Report the launch result briefly, then stop. If it fails or the session ID is unavailable, report the error without retrying or selecting another session.
