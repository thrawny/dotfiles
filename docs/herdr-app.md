# Herdr desktop

The M1 and z13 use the `thrawny` layout: the custom sidebar beside a minimal
terminal area with a minimal top tab bar (no duplicate space picker), no bottom
status bar, and pane controls on hover when split. The Monokai theme stays in place.
Home Manager installs the personal mods and reapplies
`config/herdr-app/keys.json` and `layouts/thrawny.json` on activation.
Settings, sessions, machine connections and other app state remain app-owned.
The TUI configuration still works independently.

Linux installs `herdr-app` and `herdr-core` from
[nix-pkgs](https://github.com/thrawny/nix-pkgs), not local dotfiles derivations.
Update the `thrawny-pkgs` input and run `just switch` to install a newer release.
Run `just check-herdr-app` to check the installed versions and personal mods.
macOS keeps its native app installation; both platforms share the same personal
mods, keys and layout, with fonts adapted to the host.

## Keys

Cmd means Command on macOS and Super on Linux. The complete binding inventory
is [keys.json](../config/herdr-app/keys.json); modifier ownership and platform
conflicts are in [keyboard rules](keyboard-rules.md).

| Key | Action |
| --- | --- |
| Cmd+Enter / Cmd+Shift+Enter | Split right / new tab |
| Cmd+W / Cmd+Shift+W | Close pane / close tab |
| Cmd+F | Zoom pane |
| Cmd+H/L, Ctrl+Shift+H/L | Previous / next tab |
| Cmd+U/I | Previous / next space |
| Cmd+J/K | Next / previous agent, including children |
| Cmd+1–9 | Focus the numbered agent in the sidebar |
| Cmd+O | Cycle blocked, done, working agents; oldest first in each tier |
| Cmd+Shift+J/K | Move the focused agent down / up |
| Cmd+M / Cmd+Shift+M | Cycle panes in this tab / return to the previous pane |
| Cmd+P | Projects on this machine or a connected machine |
| Cmd+Shift+P | Native command palette |
| Ctrl+A | Prefix popup, including the familiar tab, pane and agent keys |
| Ctrl+A then A, or Ctrl+A twice | Send a literal Ctrl+A |
| Ctrl+A then Shift+R | Reset manual agent ordering |

The prefix popup shows its keys. Native Ctrl shortcuts otherwise remain with
terminal programs, including unshifted Ctrl+H/J/K/L. Alt shortcuts are left
to the window manager; terminal word-navigation keys remain available.

## Plugins

- **Next agent and agent order:** the personal `thrawny-agents` mod extends
  Herdr's 0.1.10 Agents mod. Numbers and ordering use parent rows; cycling
  also visits their children. The default order follows spaces and tabs, not
  idle/working status; priority sorting is opt-in from the sort menu.
  Manual order persists in the mod's local storage; new agents follow ordered
  agents. Reset it with the prefix, or pin an agent to return to native sorting.
  Children stay nested under their parent, including after opening them in a
  normal tab. Clicking a child opens or focuses its tab; Cmd+J/K (and the prefix's
  J/K) visit children immediately after their parent, even when folded.
  Sidebar rows and tabs use the agent's session name (Pi's reported name, or
  Claude/other agents' terminal title), with explicit tab names taking precedence.
  Status indicators and pins remain.
- **Project picker:** a native popup reuses `project-picker --list` for zoxide
  history and repositories under the existing code roots. It starts on the
  focused space's machine. Enter opens a new tab in an existing project space,
  or creates a space. Shift+Enter focuses an existing space without a new tab.
  Absolute paths and `~/` paths work on the selected machine.
- **Palette and worktrees:** use the native palette and space menu's worktree
  actions. The old fzf palette and Ctrl+G worktree flow are not copied.
- **Moto driver focus:** omitted; `moto focus` addresses TUI sessions and cannot
  safely focus a native app terminal. Cmd+Shift+O remains unbound.
- **PR review queue:** the TUI plugin is enabled only on the employer machine,
  so it is not installed on the M1 or z13. The old decorator's PR/Jira metadata
  addresses TUI panes and is not copied into app terminals.

Custom agent and pane actions need the `thrawny` layout's Agents mod. Native
commands and the project picker also work in other layouts. Shipped mods and
layouts are kept intact; personal copies are never updated by Herdr itself.
