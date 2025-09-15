# Devcontainer: Build/Run Without Host Bind‑Mounts

This doc shows how to test the devcontainer and run the dotfiles installer without mounting your local repo into the container.

Prerequisites
- Docker (or compatible runtime)
- Dev Containers CLI (`npm i -g @devcontainers/cli`) or DevPod (optional)
- Optional for private clones: export `GH_TOKEN` locally

Suggested features block (example)
```json
{
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {},
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/devcontainers/features/node:1": { "version": "24" },
    "ghcr.io/duduribeiro/devcontainer-features/tmux:1": {},
    "ghcr.io/duduribeiro/devcontainer-features/neovim:1": {}
  }
}
```

Option A — Build Only (no run, no mounts)
- Create a temp dir (e.g., `/tmp/dc-test`) with `devcontainer.json`:
```json
{
  "name": "dotfiles-test",
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu-24.04",
  "remoteUser": "vscode",
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {},
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/devcontainers/features/node:1": { "version": "24" },
    "ghcr.io/duduribeiro/devcontainer-features/tmux:1": {},
    "ghcr.io/duduribeiro/devcontainer-features/neovim:1": {}
  }
}
```
- Build the image (no workspace mount occurs during build):
```
devcontainer build --workspace-folder /tmp/dc-test --image-name dotfiles-dev:local
```

Option B — Run With Named Volume (no host bind‑mount)
- Use a `devcontainer.json` like this in `/tmp/dc-test`:
```json
{
  "name": "dotfiles-test",
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu-24.04",
  "remoteUser": "vscode",
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {},
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/devcontainers/features/node:1": { "version": "24" },
    "ghcr.io/duduribeiro/devcontainer-features/tmux:1": {},
    "ghcr.io/duduribeiro/devcontainer-features/neovim:1": {}
  },
  "workspaceFolder": "/home/vscode/dotfiles",
  "workspaceMount": "source=dotfiles-test-vol,type=volume,target=/home/vscode/dotfiles"
}
```
- Start the container (still no host mount):
```
devcontainer up --workspace-folder /tmp/dc-test
```
- Clone the repo inside the container volume and run setup:
```
devcontainer exec --workspace-folder /tmp/dc-test bash -lc "git clone https://github.com/thrawny/dotfiles.git ~/dotfiles || true"
devcontainer exec --workspace-folder /tmp/dc-test bash -lc "cd ~/dotfiles && ./devcontainer/install.sh"
```
- Cleanup the volume later:
```
docker volume rm dotfiles-test-vol
```

Option C — DevPod (volume by default, convenient UX)
- Start a workspace without host mounts:
```
devpod up gh:thrawny/dotfiles --provider docker --id dotfiles-test
```
- DevPod clones the repo into a container-backed volume. If a `devcontainer.json` exists, DevPod applies features automatically.

Notes
- Private repo cloning: set `GH_TOKEN` locally and use `gh repo clone` inside the container; or add to `devcontainer.json`:
  ```json
  { "remoteEnv": { "GH_TOKEN": "${localEnv:GH_TOKEN}" } }
  ```
- The installer primes Zsh plugins (zinit) during build/run, so first SSH is fast.
- Git identity: set env before running `install.sh`: `GIT_USER=Your Name GIT_EMAIL=you@example.com`.

Troubleshooting
- Dev Containers CLI not found: `npm i -g @devcontainers/cli`.
- Permission issues with `docker-in-docker`: rebuild without that feature if not needed.
- Verify the container has the repo at `~/dotfiles` before running the installer.

