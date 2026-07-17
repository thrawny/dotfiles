# Nix Notes

The flake lives in `nix/`, not the repo root — `nix flake update <input>` must run from this directory.

- Hosts are defined in `flake.nix` (`nixosConfigurations`, plus `homeConfigurations.thrawnym1` for standalone Home Manager on macOS).
- Global packages: `home/shared/packages/{core,workstation,cloud,ai}.nix`. Host-specific packages are wired into `flake.nix` via each host's Home Manager modules.

## thrawny-pkgs input

`thrawny-pkgs` reads `github:thrawny/nix-pkgs`. To pick up a change there: commit + push in nix-pkgs → `nix flake update thrawny-pkgs` (from `nix/`) → `just switch`. There is deliberately no local-path override. nix-pkgs has a daily GHA auto-updater that pushes version bumps, so rebase local nix-pkgs commits on top of origin before pushing.

## Waybar quirks (Linux desktops)

- The binary is nix-wrapped: the process comm is `.waybar-wrapped`, so `pgrep -x waybar` finds nothing — use `pgrep -o waybar`.
- Waybar is spawned by niri, not systemd. To restart: kill it, then `niri msg action spawn -- waybar -c ~/.config/waybar/config-niri -s ~/.config/waybar/style-niri.css`.

## After changes

- Non-trivial changes: `just check` from the repo root.
- Larger NixOS changes: `just -f nix/Justfile diff` (from repo root) compares the build against `/run/current-system` with `nvd`.
