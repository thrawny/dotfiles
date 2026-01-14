# niri-switcher

GTK4 window switcher for the Niri compositor.

## Development Setup

Uses nix devshell via direnv for GTK4 dependencies.

```bash
# First time: allow direnv to create the environment cache
direnv allow

# Run tasks via mise (sources direnv's cached env)
mise run build    # cargo build --release
mise run run      # build and run
mise run nix      # clean nix build
```

## How it works

1. `.envrc` declares `use flake ../../nix#niri-switcher-dev`
2. direnv + nix-direnv caches the devshell to `.direnv/`
3. mise sources that cache via `_.source` in mise.toml

This gives nix-direnv's caching and GC protection while keeping mise for task running.
