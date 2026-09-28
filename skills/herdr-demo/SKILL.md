---
name: herdr-demo
description: Demo something live in a Herdr pane to the right, as real commands narrated by zsh comment lines.
disable-model-invocation: true
---

# Herdr demo

The user watches a demo play in a Herdr pane to the right of yours. The pane's **scrollback** is the deliverable: read top to bottom, it is a script they could rerun, with every command the demo depends on, each step introduced by a `# N. ...` comment line.

`scripts/demo-pane` in this skill's directory drives the pane. Call it by absolute path.

## Steps

1. **Outline the demo:** the point it makes and the steps that get there from a clean start, each as a `# N. ...` comment line. Explore in your own shell only to learn things (which targets exist, what an endpoint returns). Everything that creates or changes state the demo relies on (clone, pull, generate, start, clean up the last run) runs in the pane.
2. **Open the pane:** `demo-pane open` prints the pane ID. It reuses this tab's pane labelled `demo`, or creates one right of yours, then clears it. The user's focus stays where it was.
3. **Play one step at a time.** Send the comment line, then each command, with `demo-pane run <pane> '<line>' [timeout-secs]`. It types the line, waits for the prompt to come back, pauses `DEMO_PAUSE` seconds (default 1), and exits with the command's status, or 124 on timeout. After each command, read its output with `herdr pane read <pane> --source recent-unwrapped --lines 30` and write the next command from what it printed: an ID, a port, a file name. When a command surprises you, fix it in the pane under its own comment line; the fix is part of the demo. Done when the last step's output shows the point.
4. **Report:** list the steps, quote the output line that makes the point, and leave the pane open.

## Writing the commands

- **Real commands.** Type what the user would type. The narration lives in comment lines. Commands show real output, not `echo`ed stand-ins.
- **Working directory.** The pane opens in your working directory; run the demo there. Only when the demo writes files (a generated repo, saved responses), make a scratch folder one level under `/tmp` (`/tmp/hello-world`): `rm -rf /tmp/<name> && mkdir -p /tmp/<name> && cd /tmp/<name>`, so later lines use short relative paths.
- **Short lines.** Put repeated values in shell variables in their own step (`API=http://localhost:8080`), then use `$API`.
- **Pretty-print** output: `curl -sS ... | jq`, `yq` for YAML, `bat --paging=never` for files, `column -t` for tables, `grep -n` to point at a line, `curl -i` when the status code is the point.
- **Non-interactive.** A pager, editor, or prompt stalls the step until timeout: pass `--no-pager` / `--paging=never` / `-y`. To free a stuck pane: `herdr pane send-keys <pane> ctrl+c`.
- **Secrets stay in variables.** The pane is on screen and you read its scrollback, so any secret it prints is exposed. Capture a token in its own step (`TOKEN=$(gcloud auth print-identity-token)`) and send it as `-H "Authorization: Bearer $TOKEN"`. Use `curl -i` over `curl -v`, which prints request headers.
