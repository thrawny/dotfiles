---
name: nvim-here
description: Open a file at a line in the user's Neovim beside your terminal pane. Use when the user asks to open, show or jump to a file or location, or when pointing them at specific code helps more than quoting it.
---

# nvim-here

`nvim-here open` opens a file in the Neovim nearest your pane: the parent Neovim when you run in its terminal, otherwise one in your Herdr tab, then your Herdr workspace. With none near, it starts Neovim in a new pane to the right of yours.

```bash
nvim-here open src/server.go:120      # FILE, FILE:LINE or FILE:LINE:COL
nvim-here open src/server.go --line 120
```

- Paths resolve against your working directory, so run it from the checkout the file lives in.
- Each call replaces what the user sees in that window. Open the one location the user should look at now, and list any others as `file:line` in your reply.
- Add `--focus` only when the user asks to be taken there: it switches Herdr to the Neovim's tab, pulling them away from where they are.
- Add `--no-spawn` when a new pane would be unwelcome, for example from a background or scheduled task.
- The command prints where it opened the file. Pass that on in one line.
