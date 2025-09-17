---
date: 2025-09-17T18:30:23+02:00
researcher: codex-cli
git_commit: ce2842444952beec777736a84323ff5ffc06201d
branch: main
repository: dotfiles
topic: "NixOS + Hyprland + Home Manager using out-of-store symlinks with this repo"
tags: [research, codebase, home-manager, nixos, hyprland, dotfiles]
status: complete
last_updated: 2025-09-17
last_updated_by: codex-cli
---

# Research: NixOS + Hyprland + Home Manager using out-of-store symlinks with this repo

**Date**: 2025-09-17T18:30:23+02:00
**Researcher**: codex-cli
**Git Commit**: ce2842444952beec777736a84323ff5ffc06201d
**Branch**: main
**Repository**: dotfiles

## Research Question
I have a Linux laptop and want to try NixOS. I don’t currently have a tested declarative configuration. I want to get up and running with Hyprland and reuse my existing dotfiles from this repository by linking them via out-of-store symlinks. How do I get started?

## Summary
- This repo’s source-of-truth dotfiles live in `config/` and are currently symlinked by Ansible (see `ansible/all_config.yml`). We can mirror those links in Home Manager using `home.file`/`xdg.configFile` and `lib.file.mkOutOfStoreSymlink` so they reference the working tree rather than `/nix/store`.
- For NixOS + Hyprland, use a single flake with:
  - NixOS system (`nixosConfiguration`) enabling Hyprland (Wayland) and a user account.
  - Home Manager (as a NixOS module) to apply your dotfile links and optional user packages.
- Minimal first run: install NixOS (with flakes), clone this repo at `~/dotfiles`, apply the flake. Hyprland should start via your display manager or greetd, while your shell/editor/tmux/git configs come from this repo through HM out-of-store links.

## Detailed Findings
### Dotfiles layout and existing link targets
- `ansible/all_config.yml:1-24, 66-119` — Defines how files in this repo map into `$HOME` via symlinks today (e.g., `config/zsh/zshrc -> ~/.zshrc`, `config/nvim -> ~/.config/nvim`, `config/git/gitconfig -> ~/.gitconfig`). This list is the canonical map we will replicate in Home Manager. See: `ansible/all_config.yml:1-24` for core files and `:66-119` for XDG directories. 
- `config/zsh/zshrc:54-58` — Current shell config intentionally avoids `mise activate`; PATH is extended manually. This plays well with HM; we can keep Zsh behavior unchanged and just link the file. 

### Home Manager strategy (files first, then packages as desired)
- `docs/plans/nix.md:14-22, 46-63, 75-94, 101-120` — The repo’s migration plan already spells out using Home Manager with `home.file`/`xdg.configFile` and specifically shows out-of-store linking via `lib.file.mkOutOfStoreSymlink`. We will reapply that pattern for NixOS.

### Proposed NixOS + Home Manager flake (starter)
This flake integrates HM as a NixOS module, enables Hyprland, and maps your repo’s dotfiles via out-of-store symlinks. Replace `myhost` and the username as appropriate.

```nix
{
  description = "NixOS + Hyprland + HM using out-of-store dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs: let
    system = "x86_64-linux"; # or "aarch64-linux"
    username = "youruser";
  in {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      inherit system;
      specialisation = {};
      modules = [
        # Home Manager as a NixOS module
        home-manager.nixosModules.home-manager

        ({ config, pkgs, ... }: {
          networking.hostName = "myhost";
          # Wayland + Hyprland
          services.xserver.enable = false; # pure Wayland session
          programs.hyprland.enable = true;

          # Optional display manager (pick one you like). greetd is lightweight.
          services.greetd.enable = true;
          services.greetd.defaultSession = {
            command = "Hyprland";
            user = username;
          };

          # User
          users.users.${username} = {
            isNormalUser = true;
            extraGroups = [ "wheel" "video" "audio" "input" ];
          };

          # Make sure we have a modern nvim and a few basics available system-wide
          environment.systemPackages = with pkgs; [ neovim git tmux ripgrep waybar foot wl-clipboard fuzzel ];

          # Home Manager configuration for the user, including out-of-store links
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.${username} = { pkgs, lib, config, ... }: let
            repo = "${config.home.homeDirectory}/dotfiles";
          in {
            home.stateVersion = "24.05"; # adjust on upgrades

            # Files mapped to this repo via out-of-store symlinks
            home.file.".zshrc".source = lib.file.mkOutOfStoreSymlink "${repo}/config/zsh/zshrc";
            home.file.".tmux.conf".source = lib.file.mkOutOfStoreSymlink "${repo}/config/tmux/tmux.conf";
            home.file.".gitconfig".source = lib.file.mkOutOfStoreSymlink "${repo}/config/git/gitconfig";
            home.file.".gitignoreglobal".source = lib.file.mkOutOfStoreSymlink "${repo}/config/git/gitignoreglobal";

            xdg.configFile."nvim".source = lib.file.mkOutOfStoreSymlink "${repo}/config/nvim";
            xdg.configFile."ghostty".source = lib.file.mkOutOfStoreSymlink "${repo}/config/ghostty";
            xdg.configFile."direnv".source = lib.file.mkOutOfStoreSymlink "${repo}/config/direnv";
            xdg.configFile."k9s".source = lib.file.mkOutOfStoreSymlink "${repo}/config/k9s";
            xdg.configFile."starship/starship.toml".source = lib.file.mkOutOfStoreSymlink "${repo}/config/starship/starship.toml";
            home.file.".default-npm-packages".source = lib.file.mkOutOfStoreSymlink "${repo}/config/npm/default-packages";

            # Hyprland per-user config (create config/hypr in this repo)
            xdg.configFile."hypr".source = lib.file.mkOutOfStoreSymlink "${repo}/config/hypr";

            programs.zsh.enable = true; # shell; uses your .zshrc
            programs.git.enable = true; # still reads your gitconfig file
            programs.neovim.enable = true; # use your nvim config under xdg.configFile
          };
        })
      ];
    };
  };
}
```

Notes:
- The HM mapping mirrors `ansible/all_config.yml`. Add a new `config/hypr` directory to this repo for Hyprland configs (e.g., `hyprland.conf`, `hyprpaper.conf`, `waybar/`, etc.).
- Out-of-store links ensure editing files in this repo immediately affects your session (no rebuild required), which matches how you work today.

### First-run steps on a fresh NixOS install
1) Install NixOS normally and enable flakes (`nix-command flakes`) during installation.
2) Log in as your user, clone this repo to `~/dotfiles`:
   - `git clone <your-remote> ~/dotfiles`
3) Create a system flake directory (e.g., `~/nixos`) and put the flake above there as `flake.nix`.
4) Apply the system config (as root):
   - `sudo nixos-rebuild switch --flake ~/nixos#myhost`
5) Log out/in or `sudo systemctl restart greetd` to start Hyprland. Your Zsh/Nvim/Tmux/Git configs will be live via HM out-of-store links to this repo.

### Reusing existing repo behaviors
- Shell defaults and plugin bootstrapping remain as in this repo. For example, `.zshrc` ensures PATH entries and zinit plugins; no `mise activate` is used (`config/zsh/zshrc:54-58`).
- If you want HM to also own user packages, you can move Node/Python/uv, etc., into `home.packages` later (see `docs/plans/nix.md:101-120`). For a minimal start, keep packages in `environment.systemPackages` and focus HM on files.

## Code References
- `ansible/all_config.yml:1-24` — core $HOME file link map (`.zshrc`, `.tmux.conf`, `.gitconfig`, `.gitignoreglobal`).
- `ansible/all_config.yml:66-119` — XDG config link map (`.config/nvim`, `ghostty`, `direnv`, `k9s`, `starship`, `~/.default-npm-packages`).
- `config/zsh/zshrc:54-58` — No `mise activate`; PATH-only approach, zinit used for plugins.
- `docs/plans/nix.md:46-63` — Example out-of-store mapping with `lib.file.mkOutOfStoreSymlink`.
- `docs/plans/nix.md:14-22` — HM file strategy aligned to this repo.
- `devcontainer/install.sh:115-139` — Current bootstrap flow (uv, Ansible, zinit prime) for non-Nix environments; useful reference for what your HM config should replicate.

## Architecture Insights
- Source of truth is `config/` in this repo. Whether via Ansible (today) or Home Manager (NixOS), the mapping remains identical; only the orchestrator changes.
- Out-of-store links provide the same live-edit feedback loop you have now, while letting you adopt NixOS and Hyprland incrementally. You can later move run-times (Node/Python) under HM without changing file layout.
- Keeping HM embedded in NixOS (`home-manager.nixosModules.home-manager`) minimizes runtime steps: one `nixos-rebuild` applies both system and user config.

## Historical Context (optional)
- `docs/plans/nix.md` documents an ongoing plan to introduce HM in this repo. The approach above is consistent with that plan (files first, packages later, out-of-store links).

## Related Research
- docs/plans/nix.md — broader migration plan and options (nix-portable, CI images, etc.).

## Open Questions
- Display manager: do you prefer greetd, SDDM, or another DM for Hyprland startup?
- GPU/input specifics: you may need to add firmware/driver modules for your laptop’s GPU and adjust power/input settings in `nixosConfiguration`.
- HM package scope: when to migrate Node/Python/uv from system packages to HM’s `home.packages`.

## Follow-up Research 2025-09-17T18:59:30+02:00 — “Idiomatic” layout and commands

Question: What is a more idiomatic way to place the flake and repos than cloning dotfiles to `~/dotfiles` and putting a separate system flake under `~/nixos`?

Short answer: The two most common, idiomatic patterns are (A) keep your system flake under `/etc/nixos` and manage that path as a Git repo; or (B) maintain a dedicated `~/nixcfg` (or similar) repo and always invoke `nixos-rebuild --flake ~/nixcfg#<host>`. For out-of-store dotfile links, keep your dotfiles repo in a predictable place (e.g., `~/dotfiles` or nested inside the flake repo) and point Home Manager to that working tree.

Pattern A — Single repo at `/etc/nixos` (most “stock” for NixOS)
- Steps:
  - `sudo -i`
  - `rm -rf /etc/nixos && git clone <your-nixcfg-remote> /etc/nixos`
  - Ensure `/etc/nixos/flake.nix` defines `nixosConfigurations.<host>` and Home Manager.
  - Keep your dotfiles repo at `~/dotfiles` (or vendor it into `/etc/nixos/dotfiles` if you prefer one repo).
  - Switch: `sudo nixos-rebuild switch --flake /etc/nixos#<host>`
- HM out-of-store targets for separate dotfiles repo:
  - `lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/config/zsh/zshrc"` etc.

Pattern B — Dedicated repo under `$HOME` (very common for personal setups)
- Layout:
  - `~/nixcfg/flake.nix` (system + HM)
  - `~/dotfiles/` (this repo) or `~/nixcfg/dotfiles/` if you prefer a monorepo
- Switch: `sudo nixos-rebuild switch --flake ~/nixcfg#<host>`
- Pros: easier to iterate as a user; no sudo writes to Git under `/etc`.

Monorepo variant (flake + dotfiles together)
- Clone a single repo, e.g. `~/nixcfg`, with structure:
  - `flake.nix`, `flake.lock`
  - `hosts/<host>/configuration.nix`, `hardware-configuration.nix`
  - `home/users/<user>/home.nix`
  - `dotfiles/config/...` (move this repo’s `config/` under `dotfiles/`)
- HM links use: `lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nixcfg/dotfiles/config/zsh/zshrc"` (still out-of-store and live-editable).

Notes on “idiomatic”
- Using `/etc/nixos` as the canonical flake path is closest to NixOS defaults and works smoothly with typical docs/expectations.
- Keeping everything in one repo (system + HM + dotfiles) simplifies discovery, but separate repos are equally common. The deciding factor is whether you want dotfiles to remain a standalone project.
- For maximum reproducibility, you would avoid out-of-store links and let HM source files from `/nix/store`. Your choice to use out-of-store is perfectly reasonable for iterative desktop workflows; just keep a consistent path.

Recommended for your case
- Keep dotfiles as a separate repo at `~/dotfiles` (unchanged).
- Choose one of:
  - Put your flake in `/etc/nixos` (Git repo) and switch with `--flake /etc/nixos#<host>`; or
  - Create `~/nixcfg` and switch with `--flake ~/nixcfg#<host>`.
- In HM, reference dotfiles via `lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/..."`.
