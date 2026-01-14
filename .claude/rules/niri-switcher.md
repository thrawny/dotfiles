---
paths: rust/niri-switcher/**
---

# Niri Switcher Rules

## Building

Build with nix from the dotfiles/nix directory:

```bash
cd nix && nix build .#niri-switcher
```

The package is defined in `nix/flake.nix` via `mkNiriSwitcher`. System GTK4 dependencies are provided by nix.

## Testing changes

After modifying Cargo.toml or Rust source:

```bash
cd nix && nix build .#niri-switcher --no-link
```
