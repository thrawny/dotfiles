# Herdr 2 (herdr-app and herdr-core) and moto

Research from 2026-10-30, before trying the Herdr desktop app. Nothing was installed or run.

Sources:

- `herdrdev/herdr-app` at `3e32d75` (app 0.1.9)
- `herdrdev/herdr-core` (core 0.1.14)
- `herdrdev/herdr` (the 0.9 multiplexer) and its releases
- https://herdr.dev/mods/
- `bin/moto`, `bin/spawn-session`, `bin/herdr-decorator`, `nix/home/shared/herdr.nix` and `moto/claude/mods/moto-watch` in this repo

Each claim carries a mark:

- **[src]**: read in source code.
- **[docs]**: read in a README, guide or web page.
- **[inferred]**: a conclusion, not stated anywhere.

## Summary

- Herdr 2 is a new product, not a new front end for the Herdr 0.9 that moto uses. It has two parts: a desktop window, `herdr-app`, and a new headless server, herdr-core (`hc`). The app cannot see or share Herdr 0.9 workspaces, tabs or panes.
- Moving moto to Herdr 2 means porting moto from the `herdr` CLI to `hc`. The port is large, because IDs, agent status and messaging all work differently.
- Herdr mods are JavaScript panels inside the app. They suit moto's sidebar text and keys. They do not suit the watch loop or the job scheduler.
- `hc` has a documented JSON-RPC API with a schema, but no SDKs, no web UI and no mobile app.
- One `hc` core can drive work on other machines over SSH. Its message rules match moto's driver and worker model.

## Herdr 0.9, herdr-core and the app

| | Herdr 0.9.5 (today) | herdr-core (`hc`) | Herdr app (`herdr-app`) |
|---|---|---|---|
| What it is | TUI terminal multiplexer: server plus client | Headless server that runs terminals and draws nothing | Native GPU desktop window, a client of `hc` |
| Install | nix flake `herdrdev/herdr-nix` | `curl \| sh` installer, `hc update` | `curl \| sh` installer, updates itself |
| Socket | `~/.config/herdr/herdr.sock` | `<runtime dir>/<session>.sock`, or `HC_SOCKET` [src: `paths.rs`] | talks to `hc` |
| Config | `~/.config/herdr/config.toml` | `~/.config/herdr-core/` (templates) | `~/.config/herdr-app/` (layouts, `keys.json`, `settings.json`, mods) |
| Layout | workspace, tab, pane: `w1`, `w1:t1`, `w1:p1` | flat list of terminals: `t7`, a name, or `box/t7` | space, tab, pane, kept in a core document |
| Agent status | Herdr reads the screen and recognises agent kinds | Only what the program reports over OSC 7501 [src: `status.rs`] | same as core |
| Env in a pane | `HERDR_ENV`, `HERDR_PANE_ID`, `HERDR_WORKSPACE_ID`, `HERDR_TAB_ID` | `HC_TERMINAL_ID`, `HC_SOCKET` [src] | same as core |

Evidence that these are separate products:

- The core's skill says: "It is not `herdr`, the older terminal multiplexer." [src: `skills/herdr-core/SKILL.md`]
- The app's `AGENTS.md` calls it "The Herdr 2 desktop app: a native GPUI client of herdr-core." [src]
- Neither repo mentions migrating from Herdr 0.9. [src]

The app shows only `hc` terminals labelled `herdr.space=<id>`. [docs] Herdr 0.9 and Herdr 2 run side by side without conflict, because they use different binaries, sockets and config folders. [inferred]

### Is Herdr 0.9 still developed?

No one has said it ends. [docs: README and CONTRIBUTING of `herdrdev/herdr`] The signs point to a maintenance line:

- The last release is v0.9.5, from 2026-10-14. Before that, releases came every few days.
- Commits since then are fixes, tests and chores only. The last one was on 2026-10-29.
- The same team pushes to `herdr-app` and `herdr-core` several times a day. The app had 6 releases in one week. [src: `CHANGELOG.md`]

Neither Herdr 2 repo has a nix flake. Releases have telemetry on by default. [docs]

## Where moto depends on Herdr

"Breaks" means: moto unchanged, and the session moved into the app.

| Dependency | Where | Under Herdr 2 | Port to |
|---|---|---|---|
| `herdr agent list`: status, `state_change_seq` | `bin/moto` `live_agents`, `check`, `cmd_list` | Breaks | `hc ls --json`, `hc get`. Status words match, plus `error`. The `turn` counter replaces `state_change_seq` [src: `terminals.rs`] |
| `herdr agent prompt`: tell, handoff, child reports | `bin/moto` | Breaks | `hc send` (paste plus Enter) |
| `herdr agent read`, `pane read` | `bin/moto`, `spawn-session` | Breaks | `hc read <t> --lines N` |
| `herdr agent rename` | `bin/moto` | Breaks | `hc run --name`, labels |
| `herdr workspace create/list/focus`, the `workspace.move` socket call | `bin/moto`, `spawn-session` | Breaks | `herdr-app do space.new`, `space.select`, `space.move` |
| `herdr tab create/rename/close/focus` | `bin/moto`, `spawn-session` | Breaks | `herdr-app do tab.new`, `tab.rename`, `tab.close`, `tab.select` |
| `herdr pane list/get/send-keys/send-text/run` | `bin/moto`, `spawn-session`, `fork-window` | Breaks | `hc keys`, `hc send`, `hc ls` |
| `herdr agent start`, `agent wait --until` | `spawn-session` | Breaks | `hc run --bg --name <n> claude "<brief>"`, then `hc wait`. `run` sends the first task itself and reports `first_message.sent` [docs] |
| `herdr worktree create/list/remove` | `spawn-session`, `bin/moto` | Breaks | `hc` has no worktree command [src]. Use `git worktree`. The app's `worktree` mod uses the same `~/.herdr/worktrees/<repo>/<branch>` path [docs] |
| `herdr notification show` | `bin/moto` | Breaks | a mod's `notify()` |
| `herdr server reload-config` | after a home-manager switch | Not needed | The app reloads its files on save and keeps the last good version [docs] |
| Pane, tab and workspace ids in `tasks.json`, set by `moto attach` | `bin/moto` | Meaningless | Store `hc` addresses (`t7`). An address survives core recovery [docs]. Snoozed tasks need a migration |
| Hooks that test `HERDR_ENV` or `HERDR_PANE_ID` | `moto attach --hook`, `config/claude/status_line.py`, `agent-switch` hooks in `config/claude/settings.example.json` | Silent change | Under `hc` both are unset. `moto attach --hook` skips. The `agent-switch track` hooks start running, because they run only when `HERDR_ENV` is not 1 [inferred] |
| Sidebar tokens: `moto ask`, worker questions, PR, Jira, place, babysit | `bin/herdr-decorator`, through `pane.report_metadata` | Breaks | `hc` has no metadata call [src]. A clone of the app's `agents` mod can read moto's state files with `readTextFile` and `watchFolder` [docs] |
| super+shift+o runs `moto focus` (a shell binding) | `nix/home/shared/herdr.nix` | Breaks | `keys.json` has no shell action [docs]. A small mod gets the key through `nextCommand()` and runs `exec("moto", ["focus"])` [inferred] |
| super+o, super+shift+j/k, super+p, super+shift+p and host bindings (Herdr plugins) | `config/herdr/plugins`, `config/herdr/extra-plugins` | Break | `agent.next` covers super+o if a mod calls `setAgentOrder`. The palette is built in. The pickers become mods [docs] |
| `config.toml` linked by home-manager | `nix/home/shared/herdr.nix` | Not read | Link single files under `~/.config/herdr-app`. The app writes its own state into the same folder. It installs `keys.json` only when the file is missing [docs] |
| `moto job loop` in a tab of the background workspace | `bin/moto` | Moves | `hc run --bg --keep --name moto-jobs moto job loop`. The terminal survives a closed window, and after a crash it gets a fresh shell, not a rerun [docs] |

### Agent status

`hc` never reads the screen. It stores only what a program reports through OSC 7501. [src: `status.rs`] Claude Code 2.1.314 has a `programStatus` probe for OSC 7501. [src: strings in the binary] So Claude should report its own status under `hc`. [inferred] The source does not show whether `hc` answers that probe. moto's turn logic (`TURN_OVER`, `background_work`) is tuned to Herdr 0.9's screen detection. Expect behaviour changes even after a clean port. [inferred]

### Parent and child terminals

`hc` has its own parent and child model, which overlaps moto's. [docs]

- A terminal that an agent starts becomes that agent's child.
- **Children end when their parent ends, unless started with `--outlive-parent`.** If the driver spawns workers without that flag, closing the driver kills every worker. [inferred]
- The parent gets notes typed into its terminal when a child ends a turn, gets stuck or exits. The notes are tagged `<hc from="t7 name">`. [src: `notes.rs`] They would arrive beside the `[moto watch]` prompts, so moto must use them or turn them off. [inferred]

## Herdr mods compared with the moto-watch Claude Code mod

A Herdr mod is `~/.config/herdr-app/mods/<name>/main.js`. [docs: `defaults/AGENTS.md`]

- It is JavaScript that describes native GPU UI, with no DOM, no Node and no `setTimeout`.
- It reads live data (`spaces()`, `agents()`, `terminals()`), runs app commands, runs programs (`exec`), calls `hc`, fetches URLs, reads files, watches folders and keeps shared state.
- **It runs only while the app runs and its block is in the layout.** Quitting the app, a layout switch or a reload stops it. Cleanup gets at most 250 ms.
- https://herdr.dev/mods/ lists one example mod and no community mods. Herdr does not review mods. The page shows no API. The API is in `defaults/AGENTS.md` and `herdr.d.ts`, and those two agree.

| moto job | Fit for a Herdr mod | Why |
|---|---|---|
| Sidebar text (`herdr-decorator`, `moto ask`) | Good, better than today | A mod draws moto's state directly, with no TTL and no long-lived extra process [inferred] |
| super+shift+o, pickers, next agent | Good | Keys route to mods, and mods run `exec` and open popups [docs] |
| Watching workers (`moto watch` every 3 s) | Possible, worse than today | A mod stops with the app. It cannot see the driver's turns. The Claude mod delivers only between turns, through `turn.start` and `turn.complete` [src: `register.ts`] |
| Job scheduler (`moto job loop`) | Poor | It must run with no window open. A kept `hc` terminal fits better [inferred] |

Recommendation [inferred]: keep watching in the Claude Code mod and move only the display work to a Herdr mod. Since Claude Code 2.1.314, the Claude mod's `prompt.compose` hook is skipped. That loses only the mod's context section, while polling and delivery still work. A later step can replace the 3-second poll with the `hc` event stream.

## The herdr-core API

Read in `schema/README.md`, `schema/hc.openrpc.json` and `docs/security.md`.

- **JSON-RPC 2.0 over a Unix socket**, one message per line, with 32 methods. They cover terminals (run, list, get, read, send, keys, wait, interrupt, kill, attach, label), events, files, `machine.exec`, machines and documents.
- **A schema.** The API is an OpenRPC document, generated from the Rust types. `hc schema` or `rpc.discover` returns it, so you can generate a client in any language.
- **Stability.** CI fails on any change that breaks a client of the last release. The API is still marked "preview" (protocol generation 1, version 0.x).
- **Events.** `events.subscribe` streams terminal changes, status, turn ends, labels and document changes. It has sequence numbers, heartbeats and a fresh snapshot after a gap.
- **Documents.** `doc.get` and `doc.set` store JSON with version checks inside the core. The store is API-only, with no `hc` command. It could hold moto's task state.
- **Attach streams** in framed mode, so any client can draw a terminal.

What the API does not have:

- No SDK in any language. [src: searched both repos]
- No TCP or HTTP listener and no authentication of its own. Remote access is `ssh box hc connect`. [docs]
- No web UI. The app is native, and the core draws nothing. [docs]
- No mobile app. Installers exist for macOS (Apple Silicon only), Linux and Windows. [docs]

A web or phone client would need its own relay with its own authentication. [inferred]

## Several machines from one core

Read in `docs/machines.md`, `src/remote.rs` and `src/notes.rs`.

- `hc machine add user@host --name box` adds a machine over SSH, or over any pipe with `--via`. The box needs its own `hc`, and `--install` copies it there.
- The local core is the hub. `hc run --on box`, `hc read box/t3`, `hc send box/t3`, `hc exec --on box` and `hc file ... --on box` all go through it. `hc ls` and the event stream combine every machine's terminals.
- Each remote core owns its programs, history and files. Work continues if the hub sleeps or the connection drops, and the hub reconnects by itself.
- If the hub is down, nothing coordinates the boxes. The topology is a hub with spokes, not a mesh.

### Who can message whom

| Direction | Allowed | How [src] |
|---|---|---|
| Hub to remote | Any terminal | The hub forwards each call to the box (`forward_to`) |
| Remote to hub | Only the hub terminal that started work on that box | `terminal.run` on a box records it on the parent (`t.afar`). Calls from the box to anything else get `denied` |
| Remote to hub, calls | `terminal.send`, `terminal.get`, `terminal.read`, `terminal.wait` | The `CALLS_BACK` list |
| Child status to parent | Yes | The remote core sends a note over the same connection. The hub types it into the parent, tagged `<hc from="box/t7">` |
| Box A to box B | No | Remote cores know only the cores that added them. The parent relays |

No test covers the call-back path. [src: searched] Try one round trip before relying on it.

### How this maps to moto

Moto already sends everything through the driver. Workers report up, the driver tells down, and a worker messages only the workers it started. That matches the hub's rules.

| moto today | `hc` across machines |
|---|---|
| `moto spawn` opens a Herdr pane | `hc run --bg --on box --name abc-123 claude "<brief>"`, from the driver's terminal |
| `moto report` from a worker | `hc send` to the driver, one of the four allowed call-backs |
| `moto tell` | The hub sends to `box/abc-123` |
| `moto watch` every 3 s | The hub's event stream, which includes remote status and turn ends |
| Child reports to a worker's parent | Built into `hc` as parent notes |

Open points [inferred]:

- **State files are local.** A worker on a box that runs `moto report` writes that box's `tasks.json`, not the hub's. Remote workers must report through `hc send`. The document store is not in the call-back list.
- **The driver must start the workers itself.** Call-back rights go to the terminal that called `terminal.run`. Today `moto spawn` runs `spawn-session` as a separate process.
- **The hub should be always on.** A sleeping laptop hub holds every report until it wakes.
- **Worktrees and git run on each box**, through `hc exec --on box`.

## What needs rewriting

| Item | Size | Risk | Notes |
|---|---|---|---|
| A backend layer in `bin/moto` that maps list, prompt, read, focus and close onto `herdr` or `hc` | Large | High | About 40 call sites. Status meaning differs |
| `bin/spawn-session` on `hc run` | Large | High | The paste-stall workaround may not apply under `hc send`. Needs `--outlive-parent` and a decision about parent notes |
| Task state: addresses instead of ids, plus a migration | Medium | Medium | Snoozed tasks store ids too |
| `herdr-decorator` as an app mod | Medium | Low | Display only. It must call `setAgentOrder` |
| Keys: super+shift+o and the plugin bindings, as `keys.json` plus a small mod | Small | Low | Check clashes with `keys.macos.json` |
| Home-manager: app files linked one by one, no `reload-config` | Small | Medium | The installer and self-update sit outside nix |
| Claude hooks that test `HERDR_ENV` or `HERDR_PANE_ID` | Small | Medium | They fail silently, with no error |
| `moto job loop` as a kept `hc` terminal | Small | Low | |
| The driver role file and moto skills (`herdr agent read`, sidebar wording, super+shift+o) | Small | Low | Docs only |
| `fork-window`, `code-sync`, `nvim-here`, `herdr-prune-workspaces`, `project-picker`, `pr-review` | Medium | Low | Each calls `herdr` |

**If you switched today:** the driver would see no workers, and `moto list` would show every task as gone. The watch would report every pane as closed after 2 minutes. `moto spawn` would fail. The sidebar would show no questions or PRs, and super+shift+o would do nothing. [inferred]

## A safe way to try it

1. Install the app and `hc` beside Herdr 0.9. Keep the driver and workers in the Ghostty TUI. Use the app for ad hoc shells and a Claude started by hand.
2. Start Claude in the app and run `hc get <t>`. Confirm it reports idle, working, done and blocked. If it does not, the port stops here.
3. Prototype moto on an isolated core (`HC_SESSION=moto-test`), behind a setting that picks the backend. Port spawn, list, tell and watch only.
4. Try one remote worker: `hc run --on box`, reporting back with `hc send`.
5. Write the sidebar mod and the focus-key mod in a scratch `HERDR_APP_HOME`, and pass `herdr-app check` before using them.
6. Move the driver last, after `moto list` shows correct live state for a week of workers on `hc`.

## Open questions

1. Daily use or a trial only? A full port takes several days. A side-by-side trial costs nothing.
2. Is a self-updating install outside nix acceptable, with telemetry on by default? Pinning needs a custom derivation.
3. Should moto support both multiplexers for a while, or switch in one go?
4. Must the driver keep working with the window closed? Only `hc` terminals survive that, not mods.
5. Which machine is the hub: the laptop or an always-on server?
6. Should `hc`'s parent notes replace moto's child-report delivery, or stay off?
