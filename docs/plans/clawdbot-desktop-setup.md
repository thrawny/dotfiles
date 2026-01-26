# Clawdbot Cloud Gateway + Desktop Clients - Implementation Plan

## Overview

Run Clawdbot as a **Gateway** on an always-on NixOS cloud box (Hetzner), and connect desktop/laptop as **remote clients**. Optional: run a **node host** on the desktop for local command/browser execution (Helium).

## Current State

- **Desktop**: NixOS with Home Manager (managed via `modules/nixos/system.nix`)
- **Codex auth**: configured on desktop at `~/.codex/auth.json`
- **Secrets**: file-based at `~/.secrets/` (gitignored)
- **Helium browser**: installed via NUR
- **No Clawdbot**: not yet integrated
- **No cloud gateway**: not yet provisioned

## Desired End State

- **Gateway** running on a Hetzner NixOS host (`clawdbot-gateway`) as a **systemd user service**
- **Telegram provider** configured on the gateway
- **Clients** (desktop/laptop) connect via **gateway remote mode**
- **Tailscale Serve** exposes the Gateway on tailnet
- **Optional node host** on desktop for local command + Helium browser control

### Verification

```bash
# Gateway is running
systemctl --user status clawdbot-gateway

# Send "hello" via Telegram bot, expect response
```

## What We're NOT Doing

- No Spotify integration (no Linux-native plugin)
- No oracle/bird/sag plugins (keeping it minimal)
- No sops-nix/agenix (using file secrets)
- Not setting up on other hosts beyond gateway + desktop/laptop

---

## Phase 0: Decide Topology

- **Gateway host**: new Hetzner NixOS box (always-on)
- **Clients**: desktop + laptop (remote mode)
- **Optional node host**: desktop runs a node service for local execution

---

## Phase 1: Prerequisites

### 1.0 Tailscale Account

1. Create/sign in to Tailscale
2. Note your tailnet name (e.g., `tailnet-abc123.ts.net`)

### 1.1 Create Telegram Bot

1. Open Telegram, search `@BotFather`
2. Send `/newbot`
3. Choose a name and username (must end in `bot`)
4. Copy the HTTP API token

### 1.2 Get Your Chat ID

1. Start a chat with your new bot
2. Open: `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates`
3. Find `"chat":{"id":123456789}` - that number is your chat ID

### 1.3 Store the Token (on gateway)

```bash
mkdir -p ~/.secrets
echo "YOUR_TELEGRAM_TOKEN" > ~/.secrets/telegram-token
chmod 600 ~/.secrets/telegram-token
```

### Success Criteria

- [ ] Bot token saved to `~/.secrets/telegram-token` on the gateway
- [ ] Chat ID recorded
- [ ] File permissions are 600

---

## Phase 2: Home Manager Refactor (Headless-Friendly)

### 2.1 Split Desktop vs Headless HM (Gateway-safe)

The current HM default imports desktop UI modules (Hyprland/Niri/Waybar/etc). For a headless gateway, create a minimal HM module and override it on the gateway host.

**New file**: `nix/home/nixos/headless.nix`

- Import only `../shared` and any CLI-safe modules (no Wayland/UI).

**Update**: `nix/home/nixos/default.nix`

- Convert to a thin wrapper that imports `base` + `desktop` (or keep current desktop imports there).

**Update**: `nix/modules/nixos/system.nix`

- Change HM user definition to use `imports = [ ../../home/nixos/default.nix ];`
- This allows host-level overrides.

**Gateway override**: `nix/hosts/clawdbot-gateway/default.nix`

- Override the default imports (preferred with `mkDefault` in `system.nix`):

```nix
home-manager.users.${config.dotfiles.username}.imports = [
  ../../home/nixos/headless.nix
];
```

### 2.2 Auto-clone dotfiles repo (default)

Out-of-store symlinks assume `/home/<user>/dotfiles` exists. Add a Home Manager activation hook to clone the repo if missing, so fresh installs (gateway/laptop) work without manual steps.

**Update**: `nix/home/shared/default.nix` (or new `base.nix` if you split it)

- Add an activation entry that runs **before** `seedCodexConfig` and `linkGeneration`:

```nix
home.activation.ensureDotfiles = lib.hm.dag.entryBefore [
  "seedCodexConfig"
  "seedClaudeSettings"
  "seedCursorSettings"
  "linkGeneration"
] ''
  repo=${lib.escapeShellArg dotfiles}
  if [ ! -d "$repo/.git" ]; then
    ${pkgs.git}/bin/git clone --depth 1 https://github.com/jonas/dotfiles.git "$repo"
  fi
'';
```

---

## Phase 3: Provision the Cloud NixOS Gateway

### 3.1 Add a New Host Entry

**New file**: `nix/hosts/clawdbot-gateway/default.nix`

- Set hostname and basic packages
- Enable SSH and Tailscale
- Minimal example:

```nix
{ config, pkgs, ... }:
{
  networking.hostName = "clawdbot-gateway";
  services.openssh.enable = true;
  services.tailscale.enable = true;

  # add any base packages you want
  environment.systemPackages = with pkgs; [ git ];

  system.stateVersion = "24.05"; # adjust to target version
}
```

### 3.2 Add Disk Layout (disko)

Add `disko` to the flake inputs and wire it into the gateway host so `nixos-anywhere` can partition the disk.

**File**: `nix/flake.nix`

Add to inputs:

```nix
disko.url = "github:nix-community/disko";
disko.inputs.nixpkgs.follows = "nixpkgs";
```

Add `disko` to outputs function parameters.

Then add `disko.nixosModules.disko` to the gateway host modules list.

**New file**: `nix/hosts/clawdbot-gateway/disko.nix`

Use the `single-disk-ext4` template (GPT + EFI + ext4 root). Update `device` to match the Hetzner disk (prefer `/dev/disk/by-id/...` if possible):

```nix
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda"; # replace with /dev/disk/by-id/... if available
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02"; # BIOS boot partition for grub
            };
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
```

### 3.3 Wire Host into Flake

**File**: `nix/flake.nix`

- Add a new `nixosConfigurations.clawdbot-gateway`
- Follow the pattern of existing hosts (desktop/thinkpad)

Ensure the gateway host modules include:

- `disko.nixosModules.disko`
- `./hosts/clawdbot-gateway/disko.nix`
- `./hosts/clawdbot-gateway/hardware-configuration.nix` (generated by nixos-anywhere)

### 3.4 Provision via nixos-anywhere (preferred)

Use `nixos-anywhere` for a hands-off install. This lets you install directly from your laptop over SSH.

1. Create a Hetzner Cloud VM (any base image is fine, as long as SSH works).
2. Ensure you can SSH as `root` with your key.
3. Make sure the `disko` layout is present (above).
4. Run the installer from your laptop:

```bash
cd ~/dotfiles
nix run github:nix-community/nixos-anywhere -- \
  --flake ./nix#clawdbot-gateway \
  --generate-hardware-config nixos-generate-config ./nix/hosts/clawdbot-gateway/hardware-configuration.nix \
  --target-host root@<gateway-ip>
```

After the install completes, the box will reboot into NixOS.

### 3.5 Manual install fallback (ISO)

If you prefer not to use `nixos-anywhere`, attach the NixOS ISO in the Hetzner console and install manually, then deploy the flake on the box:

```bash
cd ~/dotfiles/nix
sudo nixos-rebuild switch --flake .#clawdbot-gateway
```

### 3.6 Authenticate Tailscale (Gateway)

```bash
sudo tailscale up
```

### Success Criteria

- [ ] `tailscale status` shows gateway on tailnet
- [ ] SSH into gateway works

---

## Phase 4: Add nix-clawdbot to the Flake

### 4.1 Add Flake Input

**File**: `nix/flake.nix`

```nix
nix-clawdbot.url = "github:clawdbot/nix-clawdbot";
nix-clawdbot.inputs.nixpkgs.follows = "nixpkgs";
```

### 4.2 Pass Through Outputs

Add `nix-clawdbot` to the outputs function parameters:

```nix
outputs = {
  ...
  nix-clawdbot,
  ...
}:
```

### 4.3 Add to mkHost specialArgs

```nix
specialArgs = {
  inherit
    self
    zen-browser
    walker
    nurPkgs
    xremap-flake
    nix-clawdbot
    nixpkgs-xwayland
    ;
};
```

### Success Criteria

- [ ] `nix flake metadata nix/ | rg clawdbot`
- [ ] `nix flake check nix/` evaluates

---

## Phase 5: Home Manager Configuration

### 5.1 Forward to Home Manager extraSpecialArgs

**File**: `nix/modules/nixos/system.nix`

- Add `nix-clawdbot` to function args
- Add `nix-clawdbot` to `home-manager.extraSpecialArgs`


### 4.2 Create Gateway Module

**New file**: `nix/home/nixos/clawdbot-gateway.nix`

```nix
{ nix-clawdbot, ... }:
{
  imports = [ nix-clawdbot.homeManagerModules.default ];

  programs.clawdbot = {
    enable = true;

    # Use Codex subscription (OAuth via ~/.codex/auth.json)
    defaults.model = "openai-codex/gpt-5.2-codex";

    configOverrides = {
      auth.profiles."openai-codex:default" = {
        provider = "openai-codex";
        mode = "oauth";
      };

      gateway.mode = "local";

      # Tailscale: expose gateway on tailnet
      tailscale.mode = "serve";
      gateway.auth.allowTailscale = true;
    };

    providers.telegram = {
      enable = true;
      botTokenFile = "~/.secrets/telegram-token";
      allowFrom = [ YOUR_CHAT_ID ];
    };

    systemd.enable = true;
  };
}
```

### 4.3 Create Client Module

**New file**: `nix/home/nixos/clawdbot-client.nix`

```nix
{ nix-clawdbot, ... }:
{
  imports = [ nix-clawdbot.homeManagerModules.default ];

  programs.clawdbot = {
    enable = true;

    configOverrides = {
      gateway.mode = "remote";
      gateway.remote.url = "wss://clawdbot-gateway.<tailnet>.ts.net";
    };
  };
}
```

### 4.4 Optional: Desktop Node Host

If you want commands and browser automation to run **locally on the desktop**, add a node service on the desktop host:

- Ensure Helium is installed and in `PATH`
- Add `browser.executablePath = "helium";` in the desktop node config
- Run the node as a systemd user service (if `nix-clawdbot` exposes it) or add a custom `systemd.user.services` entry

### 4.5 Import Modules

- Gateway host: import `clawdbot-gateway.nix`
- Desktop/laptop: import `clawdbot-client.nix`

### Success Criteria

- [ ] `nixos-rebuild build --flake .#clawdbot-gateway` succeeds
- [ ] `nixos-rebuild build --flake .#thrawny-desktop` succeeds

---

## Phase 5: Deploy and Verify

### 5.1 Apply Configuration (Gateway)

```bash
cd ~/dotfiles/nix
sudo nixos-rebuild switch --flake .#clawdbot-gateway
```

### 5.2 Authenticate Tailscale (Gateway)

```bash
sudo tailscale up
```

### 5.3 Apply Configuration (Desktop/Laptop)

```bash
cd ~/dotfiles/nix
sudo nixos-rebuild switch --flake .#thrawny-desktop
```

### 5.4 Verify Services

```bash
# Gateway status
systemctl --user status clawdbot-gateway

# Gateway logs
journalctl --user -u clawdbot-gateway -f
```

### 5.5 Test via Telegram

1. Send "hello" to your bot
2. Expect a response from Clawdbot
3. If desktop node is enabled: "open browser and go to github.com"

### Success Criteria

- [ ] Tailscale connected on gateway
- [ ] Clawdbot gateway active
- [ ] Telegram "hello" receives response
- [ ] Optional: desktop node can execute commands

---

## Phase 6: Migration / Rebuild

To move the gateway to a bigger box:

1. Backup:
   - `~/.clawdbot/` (sessions/config)
   - `~/.secrets/telegram-token`
   - `~/.codex/auth.json`
2. Provision new box + apply flake
3. Restore backups
4. Re-auth Tailscale and confirm tailnet DNS

---

## Phase 7: Rollback (If Needed)

### 7.1 Quick Disable

```bash
systemctl --user stop clawdbot-gateway
systemctl --user disable clawdbot-gateway
```

### 7.2 Full Removal

1. Remove imports from host configs
2. Delete `nix/home/nixos/clawdbot-gateway.nix` and `nix/home/nixos/clawdbot-client.nix`
3. Optionally remove flake input `nix-clawdbot`
4. Rebuild

---

## Testing Strategy

### Unit Tests
- `nix flake check nix/`
- `nixos-rebuild build --flake .#clawdbot-gateway`

### Integration Tests
- Gateway service starts and stays running for 60s
- Telegram message round-trip works

### Manual Testing Steps
1. Send "what time is it" via Telegram
2. Send "take a screenshot" (if a node host is enabled)
3. Send "open browser and go to news.ycombinator.com" (desktop node)
4. Access WebChat from another device: `https://clawdbot-gateway.<tailnet>.ts.net`
5. Send nonsense - verify graceful handling

---

## References

- nix-clawdbot repo: https://github.com/clawdbot/nix-clawdbot
- Clawdbot docs: https://docs.clawd.bot
- Pattern reference: `nix/home/nixos/default.nix` (xremap integration)
- extraSpecialArgs pattern: `nix/modules/nixos/system.nix`
