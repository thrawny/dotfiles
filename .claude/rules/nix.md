---
paths: nix/**/*.nix
---

# Nix Configuration Rules

## After every change
- Run `mise nix:check` - formats, lints, and evaluates config

## Only when requested
- `mise dry` - full build test (NixOS only)
- `mise switch` - apply changes
