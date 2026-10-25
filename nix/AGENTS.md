# Nix Notes

The flake lives in `nix/`, not the repo root — `nix flake update <input>` must run from this directory.

- Hosts are defined in `flake.nix` (`nixosConfigurations`, plus `homeConfigurations.thrawnym1` for standalone Home Manager on macOS).
- Global packages: `home/shared/packages/{core,workstation,cloud,ai}.nix`. Host-specific packages are wired into `flake.nix` via each host's Home Manager modules.

## thrawny-pkgs input

`thrawny-pkgs` reads `github:thrawny/nix-pkgs`. To pick up a change there: commit + push in nix-pkgs → `nix flake update thrawny-pkgs` (from `nix/`) → `just switch`. There is deliberately no local-path override. nix-pkgs has a daily GHA auto-updater that pushes version bumps, so rebase local nix-pkgs commits on top of origin before pushing.

## Binary caches

`lib/nix-caches.nix` holds the one list. `modules/system.nix` reads it for NixOS. On macOS no module can, because Determinate Nix owns `/etc/nix/nix.conf` and the Macs set `nix.enable = false`. There, `just install-nix-caches` appends a delimited block to `/etc/nix/nix.custom.conf`. Run it once per machine, and again after editing the list. If you skip it, every `llm-agents.nix` package (codex, claude-code) builds from source.

## macOS Linux builder

`hosts/thrawnym1/linux-builder.nix` runs the Rosetta VM through launchd while leaving Determinate in charge of Nix. Its builder registration is included from `/etc/nix/nix.custom.conf`. `packages/linux-builder.nix` targets macOS 15 explicitly because the upstream cached VM launcher requires a newer macOS. The guest uses Linux 6.12 because Rosetta on macOS 15 crashes with Linux 6.13+. Bootstrapping this customized guest requires an ARM Linux builder (the unmodified upstream VM works for ARM builds). `just build-linux-builder` builds the launcher; after `just switch`, `just check-linux-builder` forces an x64 Linux smoke build.

## Waybar quirks (Linux desktops)

- The binary is nix-wrapped: the process comm is `.waybar-wrapped`, so `pgrep -x waybar` finds nothing — use `pgrep -o waybar`.
- Waybar is spawned by niri, not systemd. To restart: kill it, then `niri msg action spawn -- waybar -c ~/.config/waybar/config-niri -s ~/.config/waybar/style-niri.css`.

## After changes

- Non-trivial changes: `just check` from the repo root.
- Larger NixOS changes: `just -f nix/Justfile diff` (from repo root) compares the build against `/run/current-system` with `nvd`.
