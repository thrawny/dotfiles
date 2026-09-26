---
description: Fork this conversation into a Herdr tab or Hyprland window
allowed-tools: Bash(fork-window:*)
disable-model-invocation: true
---

Run this command once in the current working directory:

```bash
fork-window claude '${CLAUDE_SESSION_ID}'
```

It forks this conversation into a separate session, shares the checkout, and sends the fork a notice to wait for new instructions. The original session stays open.

Report the launch result briefly, then stop. If it fails, report the error without retrying or selecting another session.
