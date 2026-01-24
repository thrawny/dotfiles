# Plan: Extract agent-switch to Separate Repo

## Current State

agent-switch lives in `rust/agent-switch/` within dotfiles. The Nix flake builds it via crane with dependency caching.

## Goal

Move to a separate repo (e.g., `github:thrawny/agent-switch`) while supporting local development overrides.

## Flake Input Options

### Option A: Flake with packages (recommended)

Separate repo exports its own packages:

```nix
# agent-switch/flake.nix
{
  inputs = { nixpkgs.url = "..."; crane.url = "..."; };
  outputs = { ... }: {
    packages.x86_64-linux.default = ...;
    overlays.default = final: prev: { agent-switch = ...; };
  };
}

# dotfiles/flake.nix
inputs.agent-switch.url = "github:thrawny/agent-switch";
```

### Option B: Source-only input

Keep build logic in dotfiles, just reference source:

```nix
inputs.agent-switch-src = {
  url = "github:thrawny/agent-switch";
  flake = false;
};

# In mkAgentSwitch:
src = craneLib.cleanCargoSource agent-switch-src;
```

## Local Override Methods

### CLI override (no file changes)

```bash
nix build --override-input agent-switch path:/home/thrawny/agent-switch
just switch --override-input agent-switch path:/home/thrawny/agent-switch
```

### Per-host declarative override

Add module option:

```nix
# modules/nixos/agent-switch.nix
options.dotfiles.agentSwitchSrc = lib.mkOption {
  type = lib.types.nullOr lib.types.path;
  default = null;
};

config = lib.mkIf (config.dotfiles.agentSwitchSrc != null) {
  nixpkgs.overlays = [
    (final: prev: {
      agent-switch = mkAgentSwitch final config.dotfiles.agentSwitchSrc;
    })
  ];
};
```

Then in host config:

```nix
# hosts/desktop/default.nix
dotfiles.agentSwitchSrc = /home/thrawny/agent-switch;
```

### Justfile helper

```just
agent_switch_override := if path_exists(".use-local-agent-switch") == "true" {
    "--override-input agent-switch path:" + `cat .use-local-agent-switch`
} else { "" }

switch:
    sudo nixos-rebuild switch --flake . {{ agent_switch_override }}
```

## Migration Steps

1. Create `github:thrawny/agent-switch` with flake.nix
2. Add as flake input to dotfiles
3. Remove `rust/agent-switch/` from dotfiles
4. Test with `--override-input` for local dev
5. Optionally add per-host override module
