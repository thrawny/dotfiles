# Repository Guide

Cross-platform dotfiles managed with Nix Home Manager (`nix/`). See `nix/AGENTS.md` for nix specifics.

- Task runner is `just`, always from the repo root — if a command is missing, add a recipe rather than `cd`ing into subdirectories.
- Commit and push every dotfiles change directly to `main` by default. Use a pull request only when explicitly requested. Before reporting completion, verify the working tree is clean and the branch is up to date with its upstream. If pushing is blocked, report the blocker.
- Outside the sandbox, run `just switch-hm` or `just switch` without asking permission. Prefer `just switch-hm` for Home Manager-only changes. When `SANDBOX=1`, ask Jonas to run local activation outside the sandbox; remote deployments are allowed.
- `bin/` is for runtime commands needed on `PATH`. Development and validation helpers go in `scripts/` or the owning component's `scripts/` directory, invoked through `just`.
- Scripts of 50+ lines live in standalone files; Nix exposes or configures them rather than containing the implementation.
- For custom desktop shell changes, including its Nix wiring, read [shell/AGENTS.md](shell/AGENTS.md).
- Before changing keyboard bindings, modifier remaps, or terminal key passthrough, read [keyboard rules](docs/keyboard-rules.md).
- This repo is public. Employer values (GitHub org and team, Jira site, internal repo names) live in the private `~/.config/work/config.toml`, read with `bin/work-config`. Code, tests, comments and commit messages use placeholders such as `acme/widgets` and `ABC-123`.

## Tests

Every test is code someone has to keep working, so a change ships without new tests by default. Check it by running it: the command itself, a reload, or a smoke test in the real app.

Add a test only when Jonas asks for one, or when all three hold:

1. The code is logic that can be wrong while still running cleanly: parsing, a state machine, ranking or ordering, or a check that runs before deleting or overwriting something.
2. A break would go unnoticed until it did damage. A keybinding, a launch or a config value breaks visibly on next use, so it gets no test.
3. The test can call that logic directly, or drive real local tools such as git in a temp directory, headless Neovim or offscreen Qt.

A bug fix earns a test only when the bug passes the same three conditions.

How to write one:

- Add it to the component's existing suite. Start a new test file only when the component has no suite.
- Search the suite first and extend an existing test when one already covers the behaviour.
- Assert outcomes: a return value, a file written, the state left behind. Message wording, glyphs, sizes, call order, mock arguments and config values stay unasserted.
- Keep fakes to a few lines at the edge. When a test would need a fake that answers like an external tool, such as a fake `gh` that mimics GitHub's API, move the logic into a function that takes plain data and test that, or write no test.
- Keep it deterministic, with no network and no real sleeps.
- Run the suite, then name each added test in your final message with the condition it meets.

When a change breaks an existing test, update it if it meets these rules and delete it if it doesn't.

## Source → target

Two symlink styles, and the difference matters:

- **Mutable** (`mkOutOfStoreSymlink`, edit takes effect immediately): `config/claude/` → `~/.claude/`, `config/codex/` → `~/.codex/`, `config/pi/` → `~/.pi/agent/`, `config/hypr/` → `~/.config/hypr/{hyprland.lua,lua/}` (Hyprland Lua config; `hyprlock.conf` stays Nix-generated).
- **Immutable** (store-backed, needs `just switch` to take effect): `config/nvim/lua` is copied into the nix-built Neovim package (`nix/lib/nvim-package.nix`); each folder in `skills/` → `~/.claude/skills/<skill>`, `~/.pi/agent/skills/<skill>`, `~/.codex/skills/<skill>` per the selection in `nix/lib/agent-skills.nix`; `config/codex/commands/` → `~/.codex/skills/` only.

`moto job` schedules work: job files live in `$MOTO_HOME/jobs/`, not here, and
`just moto-jobs-dev` runs the scheduler in the foreground for iteration.
`moto when` adds a one-off check that the same scheduler runs until it passes or expires. It lives in moto's state folder (`~/.local/state/moto/when.json`), so it needs no file in `$MOTO_HOME`. `moto job list` shows it, and `moto job rm` cancels it.

`moto/skills/` is outside Home Manager: `moto link` symlinks each skill into `~/.claude/skills/`, and a skill of the same name in `$MOTO_HOME/skills/` replaces it. Run `moto link` after adding or renaming one.

Zsh, ghostty, direnv, starship etc. are generated entirely by Nix — no files in `config/`; edit the module in `nix/`.

## Theme

Colors live in one canonical document, `nix/themes/monokai.json` (semantic/syntax/terminal/diff roles plus per-app `applications` overrides). `nix/lib/theme.nix` loads and validates it; Home Manager passes it to modules as the `theme`/`themeLib` args and publishes a runtime copy at `~/.config/dotfiles/theme.json` for mutable consumers (Neovim fallback, the Pi status line). Never add `#RRGGBB` literals to themed consumers — edit the theme and run `just switch`; `just check-theme` enforces this.

`config/claude/` is the user's global `~/.claude/`; `.claude/` in this repo is project-specific and not symlinked anywhere.

## Example/live settings pairs

Claude (`config/claude/settings.example.json`), Codex (`config/codex/config.example.toml`), and Pi (`config/pi/settings.example.json`) each have a gitignored live counterpart without the `example` infix. Update the example first, then update the live file by default without asking. Only leave the live file unchanged when the user explicitly requests it.
