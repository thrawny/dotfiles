---
paths: nix/**/*.nix
---

# Nix Configuration Rules

## After every change
- Run `mise nix:check` (fast ~1s) - formats and lints

## Before committing or after significant changes
- Run `mise check-hm` to evaluate the config and catch Nix errors

## Only when requested
- `mise dry` - full build test (slow)
- `mise switch` / `mise switch-hm` - apply changes
