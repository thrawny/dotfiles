---
name: herdr-demo
description: Demo something live in a Herdr pane to the right, as real commands narrated by zsh comment lines.
disable-model-invocation: true
---

# Herdr demo

The user watches a demo play in a Herdr pane to the right of yours. The pane's **scrollback** is the deliverable: read top to bottom, it is a script they could rerun, with every command the demo depends on, each step introduced by a `# N. ...` comment line.

`scripts/demo-pane` in this skill's directory drives the pane. Call it by absolute path.

## Steps

1. **Write the script.** Explore in your own shell only to learn things (which targets exist, what an endpoint returns). Everything that creates or changes state the demo relies on (clone, pull, generate, start, clean up the last run) goes in the script. Done when every step is a comment line plus the real commands that show it.
2. **Open the pane:** `demo-pane open` prints the pane ID. It reuses this tab's pane labelled `demo`, or creates one right of yours, then clears it. The user's focus stays where it was.
3. **Play each line**, comments included: `demo-pane run <pane> '<command>' [timeout-secs]`. It types the line, waits for the prompt to come back, pauses `DEMO_PAUSE` seconds (default 1), and exits with the command's status, or 124 on timeout.
4. **Check the scrollback:** `herdr pane read <pane> --source recent-unwrapped --lines 200`. Done when every step printed what its comment promised. When a step went wrong, fix the script and replay it from step 2, so the scrollback stays one clean run.
5. **Report:** list the steps, quote the output line that makes the point, and leave the pane open.

## Writing the script

- **Real commands.** Type what the user would type. The narration lives in comment lines. Commands show real output, not `echo`ed stand-ins.
- **Scratch folder** is `/tmp/<name>`, one level under `/tmp` (`/tmp/hello-world`). Open with `rm -rf /tmp/<name> && mkdir -p /tmp/<name> && cd /tmp/<name>` so later lines use short relative paths.
- **Short lines.** Put repeated values in shell variables in their own step (`API=http://localhost:8080`), then use `$API`.
- **Pretty-print** output: `curl -sS ... | jq`, `yq` for YAML, `bat --paging=never` for files, `column -t` for tables, `grep -n` to point at a line, `curl -i` when the status code is the point.
- **Non-interactive.** A pager, editor, or prompt stalls the step until timeout: pass `--no-pager` / `--paging=never` / `-y`. To free a stuck pane: `herdr pane send-keys <pane> ctrl+c`.
- **Secrets stay in variables.** The pane is on screen and you read its scrollback, so any secret it prints is exposed. Capture a token in its own step (`TOKEN=$(gcloud auth print-identity-token)`) and send it as `-H "Authorization: Bearer $TOKEN"`. Use `curl -i` over `curl -v`, which prints request headers.
