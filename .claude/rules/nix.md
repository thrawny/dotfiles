---
paths: nix/**/*.nix
---

# Nix Configuration Rules

## After every change
- Run `mise nix:check` (fast ~1s) - formats and lints

## Before committing or after significant changes
- Run `mise check` to evaluate the config and catch Nix errors

## Only when requested
- `mise dry` - full build test (NixOS only)
- `mise switch` - apply changes
