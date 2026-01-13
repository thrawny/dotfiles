---
paths: nix/**/*.nix
---

# Nix Configuration Rules

## After every change
- Run `just nix-check` - formats, lints, and evaluates config

## Only when requested
- `just dry` - full build test (NixOS only)
- `just switch` - apply changes
