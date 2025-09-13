# Nix/Home Manager Migration Plan

This document captures our plan to migrate the dotfiles repo from Ansible-first to Home Manager–first, while preserving rootless installs and keeping container builds green. It consolidates decisions and options discussed so far.

## Goals & Constraints
- Rootless first: install.sh must work without root and without assuming Nix is present.
- Keep Docker builds working: the Dockerfile should continue to succeed without requiring Nix at runtime.
- Ditch mise for runtime management: use Home Manager for Node/Python/etc. when Nix is available; provide a tiny non-Nix fallback for Node so global CLIs (claude/codex) work anywhere.
- Preserve current repo layout: continue editing source files under `config/` (and related dirs); declarative tooling references those files.
- Minimal behavioral surprises: keep zsh/zinit, Neovim config, and general UX consistent.

## Approach Overview (Phased)
1) Add Home Manager alongside Ansible, no behavior change by default.
   - Create `hm/flake.nix` and `hm/modules/*` that map existing `config/` files into `$HOME` using `home.file` and `xdg.configFile`.
   - Enable a small set of programs (zsh, git, neovim, tmux, starship) via HM but still read our repo’s files for configuration.
2) Bootstrap logic in `devcontainer/install.sh` (HM preferred, Ansible fallback).
   - If `DOTFILES_HM=1` and `nix` exists → run `home-manager switch --flake hm#<profile>`.
   - Else if `DOTFILES_HM=1` and `DOTFILES_USE_NIX_PORTABLE=1` → attempt nix-portable (best-effort; see caveats).
   - Else → run current Ansible playbook for symlinks (status quo).
   - Provide a non-Nix Node fallback (downloaded tarball) to keep `claude-code`/`codex` working without mise.
3) Keep Docker build on the non-Nix path by default to avoid runtime dependencies.
   - Optionally add a separate build target that uses Nix in a builder stage and copies closures into the final image (recommended pattern below).
4) Gradual migration of responsibilities from Ansible to HM.
   - Start with file linking only. Over time, let HM own more packages and program configs.
5) Flip default to HM after burn-in, keep `--fallback-ansible` switch.

## Container Strategy (Nix without runtime dependency)
Recommended: builder-stage Nix, Nix-free runtime
- Stage A (builder): use a Nix-capable image (nixos/nix or a nix-portable bootstrap) to run `home-manager build/switch` for user `vscode`.
  - Produces HM links under `/home/vscode` pointing into `/nix/store`.
- Stage B (final): our devcontainers base (Ubuntu 24.04) that copies the required `/nix/store` closures plus `/home/vscode` from Stage A.
  - Result: No Nix daemon or wrapper needed at runtime; HM links resolve normally.

Alternatives (less preferred)
- nix-portable at runtime: wrap the login shell so `/nix/store` is projected by bwrap/proot. Works but adds overhead and fragility.
- Bake Nix into the runtime image: simplest but ships Nix you may not need at runtime.

When nix-portable may not work
- User namespaces and ptrace both disabled (some CI/builders) → bwrap and proot unavailable.
- macOS hosts (outside containers) aren’t supported by nix-portable.
- Expecting plain shells to see `/nix/store` with nix-portable: links resolve only inside the wrapper unless closures are copied into the image.

## DevPod Runtime Integration
- DevPod flow: DevPod checks out dotfiles, then runs `devcontainer/install.sh`.
- Recommended default for DevPod today:
  - Use Home Manager at runtime for dotfiles only (no packages), with out-of-store symlinks so links point to the checked-out repo and work in a plain shell.
  - Then install missing runtimes (e.g., Node) via `mise` non-interactively: run `mise trust` and `mise use -g node@<ver>`. Do not use `mise activate`.
- Detection and flags:
  - `DEVPOD=1` set by environment → prefer HM at runtime for dotfiles.
  - `DOTFILES_HM=1` → enable HM path; `DOTFILES_USE_NIX_PORTABLE=1` allows HM without preinstalled Nix.
  - `HM_PACKAGES=0` (default for DevPod) → HM files only; install runtimes with `mise` if missing.

Example HM out-of-store mapping (works in plain shells):
```nix
{ config, lib, ... }:
let
  repo = "${config.home.homeDirectory}/dotfiles";
in {
  home.file.".zshrc".source = lib.file.mkOutOfStoreSymlink "${repo}/config/zsh/zshrc";
  xdg.configFile."nvim".source = lib.file.mkOutOfStoreSymlink "${repo}/config/nvim";
}
```

## Repo Layout (proposed HM files)
- `hm/flake.nix` – flake inputs/outputs and `homeConfigurations` for Linux/Darwin users.
- `hm/modules/`
  - `files.nix` – map `config/` files into `$HOME` via `home.file` and `xdg.configFile`.
  - `shell.nix` – zsh environment, aliases, prompt-related env vars.
  - `git.nix` – optional program settings if not using committed `gitconfig`.
  - `editor.nix` – Neovim package selection; config still in `config/nvim`.
  - `tmux.nix`, `starship.nix` – program toggles.
  - `tools.nix` – packages (Node/Python/uv/ripgrep/tmux/starship/gh etc.).

## Home Manager: File Mapping (mirrors current layout)
Example `hm/modules/files.nix` snippet:
```nix
{ config, lib, pkgs, ... }:
{
  home.stateVersion = "24.05";
  # Shell and tmux
  home.file.".zshrc".source = ../config/zsh/zshrc;
  home.file.".tmux.conf".source = ../config/tmux/tmux.conf;

  # Git
  home.file.".gitconfig".source = ../config/git/gitconfig;
  home.file.".gitignoreglobal".source = ../config/git/gitignoreglobal;

  # XDG configs
  xdg.configFile."nvim".source = ../config/nvim;
  xdg.configFile."ghostty".source = ../config/ghostty;
  xdg.configFile."direnv".source = ../config/direnv;
  xdg.configFile."k9s".source = ../config/k9s;
  xdg.configFile."starship/starship.toml".source = ../config/starship/starship.toml;

  # Extras
  home.file.".default-npm-packages".source = ../config/npm/default-packages;
}
```

## Home Manager: Packages (replace mise)
Example `hm/modules/tools.nix` snippet:
```nix
{ config, pkgs, ... }:
{
  home.packages = with pkgs; [
    nodejs_22 pnpm yarn
    python312 uv
    ripgrep tmux neovim starship gh zsh
  ];

  # Global npm/pnpm bins under ~/.local (safe, rootless)
  home.sessionVariables = {
    NPM_CONFIG_PREFIX = "${config.home.homeDirectory}/.local/npm";
    PNPM_HOME = "${config.home.homeDirectory}/.local/share/pnpm";
  };
  home.sessionPath = [
    "${config.home.homeDirectory}/.local/npm/bin"
    "${config.home.homeDirectory}/.local/share/pnpm"
  ];
}
```
Notes
- HM manages Node/Python versions; no `mise` needed.
- Keep `direnv` disabled by default or minimal if desired (we are not using `mise` as a direnv replacement).

## Flake Skeleton (illustrative)
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager }:
  let
    mkHome = { system, username, extraModules ? [ ] }:
      home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { inherit system; };
        modules = [
          ./modules/files.nix
          ./modules/shell.nix
          ./modules/git.nix
          ./modules/editor.nix
          ./modules/tmux.nix
          ./modules/starship.nix
          ./modules/tools.nix
          { home.username = username; home.homeDirectory = "/home/${username}"; }
        ] ++ extraModules;
      };
  in {
    homeConfigurations."vscode@linux" = mkHome { system = "aarch64-linux"; username = "vscode"; };
    homeConfigurations."thrawny@darwin" = mkHome { system = "aarch64-darwin"; username = "thrawny"; };
  };
}
```

## install.sh: Bootstrap Logic (target state)
Behavior: prefer HM when available or explicitly requested; otherwise fall back to Ansible + minimal runtime bootstrap. Split by environment.

Pseudocode
```bash
if [[ "${DOTFILES_HM}" == 1 ]]; then
  if command -v nix >/dev/null; then
    home-manager switch --flake hm#${HM_PROFILE:-vscode@linux}
    hm_applied=1
  elif [[ "${DOTFILES_USE_NIX_PORTABLE}" == 1 ]]; then
    np="$HOME/.local/bin/nix-portable"; curl -fsSL -o "$np" https://example.com/nix-portable; chmod +x "$np"
    "$np" run home-manager -- switch --flake hm#${HM_PROFILE:-vscode@linux} && hm_applied=1 || true
  fi
fi

# Files: If HM not applied, fall back to Ansible symlinks
if [[ -z "${hm_applied:-}" ]]; then
  uv sync
  uv tool install --editable .
  ansible-playbook ansible/main.yml
fi

# Runtimes: choose strategy per environment
if [[ "${HM_PACKAGES:-0}" == 1 ]]; then
  : # HM owns packages; nothing to do
else
  if command -v mise >/dev/null; then
    mise trust "$HOME/dotfiles/.mise.toml" || true
    command -v node >/dev/null || mise use -g "node@${DOTFILES_NODE_VERSION:-24}"
  else
    ensure_node_tarball_fallback   # see below
  fi
  npm -g install @anthropic-ai/claude-code @openai/codex || true
fi
```

### Flags & Detection
- `DEVPOD=1`: set by DevPod; prefer HM-for-files at runtime.
- `DOTFILES_HM=1`: attempt HM path; default to `1` for DevPod use.
- `DOTFILES_USE_NIX_PORTABLE=1`: allow HM without preinstalled Nix (uses nix-portable).
- `HM_PROFILE`: name of the HM profile to switch to (e.g., `vscode@linux`).
- `HM_PACKAGES=1`: HM manages packages; set when devcontainer is Nix-compatible. If `0`, use `mise` or tarball fallback for Node.

Node tarball fallback (rootless)
```bash
ensure_node_tarball_fallback() {
  if command -v node >/dev/null; then return; fi
  ver="${DOTFILES_NODE_VERSION:-22.11.0}"
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)
  case "${arch}" in x86_64) arch=x64;; aarch64|arm64) arch=arm64;; *) echo "Unsupported arch: $arch"; return 1;; esac
  base="node-v${ver}-${os}-${arch}"
  url="https://nodejs.org/dist/v${ver}/${base}.tar.xz"
  prefix="$HOME/.local/node/${ver}"
  mkdir -p "$prefix" "$HOME/.local/bin"
  curl -fsSL "$url" | tar -xJ -C "$prefix" --strip-components 1
  export PATH="$prefix/bin:$HOME/.local/bin:$PATH"
  export NPM_CONFIG_PREFIX="$HOME/.local/npm"
}
```

Notes
- We already removed `mise activate` from `config/zsh/zshrc` and only expose shims/paths as needed.
- For non-Nix hosts, Node tarball fallback + `NPM_CONFIG_PREFIX` keeps global CLIs working without touching system paths.

## Dockerfile & Devcontainer
- Keep the current image based on `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`.
- Neovim: installed via PPA to get a modern version; Lazy.nvim primes during build.
- Node CLIs (`@anthropic-ai/claude-code`, `@openai/codex`) install via npm with a user prefix.
- Default build path uses Ansible and does not require Nix.
- Optional future: a multi-stage target that runs HM in a Nix builder and copies `/nix/store` into the final image to test HM in CI without runtime Nix.

## Two Operating Modes Going Forward
1) DevPod (today): HM for dotfiles at runtime + `mise` for missing runtimes
   - Pros: fast startup, minimal image changes, no wrapper shells
   - Cons: keeps a small dependency on `mise`
2) Nix-compatible Devcontainers: HM for dotfiles and packages; remove `mise`
   - Implementation:
     - Base image with Nix; or
     - Builder-stage Nix that bakes `/nix/store` into the runtime image (preferred for UX); or
     - nix-portable wrapper at runtime (least preferred)
   - Pros: single source of truth via HM; no `mise`
   - Cons: image/runtime must support Nix or include baked store closures

## Removing mise (conditional)
- DevPod today: keep `mise` only as a runtime installer (no shell activation) for gaps like Node.
- Nix-compatible containers: remove `mise` entirely once HM owns packages.
- Zsh: keep `config/zsh/zshrc` free of `mise activate` (already done).
- npm global prefix: keep under `~/.local/npm` to avoid system writes.

## Effort & Milestones
- Phase 1 (HM skeleton + file mapping): 2–4 hours.
- Phase 2 (install.sh switches + Node tarball fallback): 1–2 hours.
- Phase 3 (packages via HM; Docker optional HM target): 0.5–1 day.
- Phase 4 (flip default to HM, Ansible optional): after 1–2 weeks of use.

## Open Questions
- Package scope in HM: how much should HM own vs. leave to system/package managers?
- macOS system-level settings: use HM only or add nix-darwin later?
- CI path: do we want a separate HM-only Docker target (bigger image, but fully declarative)?

## Acceptance Criteria
- Rootless `devcontainer/install.sh` works on hosts without Nix (Docker build remains green).
- DevPod: HM applies dotfiles at runtime with out-of-store links; Node available via `mise` or fallback.
- Nix-compatible containers: HM manages packages and files; no `mise` present.
- Node CLIs work in both paths (HM packages or fallback), without `mise activate` prompts.

## Next Steps
- Scaffold `hm/flake.nix` and `hm/modules/*` mirroring `config/`.
- Add `DOTFILES_HM` and `DOTFILES_USE_NIX_PORTABLE` branches to `devcontainer/install.sh`.
- Implement `ensure_node_tarball_fallback` in `devcontainer/install.sh`.
- Optionally add a multi-stage HM Docker target for CI experiments.

---

### Appendix A: Example HM Commands
- Switch to HM config (when Nix present):
  - `home-manager switch --flake hm#vscode@linux`
  - `home-manager switch --flake hm#thrawny@darwin`

### Appendix B: Multi-Stage Docker (sketch)
```
# Stage A: Nix builder
FROM nixos/nix AS hm-builder
RUN useradd -m vscode && su - vscode -c "nix --version"
COPY . /home/vscode/dotfiles
USER vscode
RUN nix --extra-experimental-features 'nix-command flakes' \
    build /home/vscode/dotfiles/hm#homeConfigurations."vscode@linux".activationPackage

# Stage B: Runtime (no Nix)
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04
COPY --from=hm-builder /nix/store /nix/store
COPY --from=hm-builder /home/vscode /home/vscode
USER vscode
```

### Appendix C: Current State Recap
- Dockerfile: devcontainers Ubuntu 24.04 base, newer Neovim via PPA, Node CLIs installed, user `vscode`.
- zshrc: no `mise activate`; shims no longer auto-activated.
- install.sh: still Ansible-first; we will add HM path and Node tarball fallback next.
