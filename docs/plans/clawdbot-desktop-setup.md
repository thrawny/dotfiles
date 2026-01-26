# Clawdbot Desktop Setup - Implementation Plan

## Overview

Set up Clawdbot on the NixOS desktop (`thrawny-desktop`) using OpenAI Codex for AI and Telegram for messaging. This enables controlling the desktop via Telegram messages, with browser automation capabilities.

## Current State

- **Desktop**: NixOS with Home Manager integrated via `modules/nixos/system.nix`
- **Codex auth**: Already configured at `~/.codex/auth.json` (OAuth)
- **Secrets**: File-based in `~/.secrets/` (gitignored pattern)
- **Helium browser**: Installed via NUR (`nurPkgs.repos.Ev357.helium`)
- **No Clawdbot**: Not yet integrated

## Desired End State

- Clawdbot running as a systemd user service on desktop
- Responds to Telegram messages from your chat ID
- Uses Codex subscription (no separate API key needed)
- Browser control via Helium (ungoogled-chromium)

### Verification

```bash
# Service running
systemctl --user status clawdbot-gateway

# Send "hello" via Telegram bot, expect response
```

## What We're NOT Doing

- No Spotify integration (no Linux-native plugin)
- No oracle/bird/sag plugins (keeping it minimal)
- No sops-nix/agenix (using simple file secrets)
- Not setting up on other hosts (thinkpad, asahi) yet

---

## Phase 1: Prerequisites - Telegram Bot Setup

### 1.1 Create Telegram Bot

1. Open Telegram, search for `@BotFather`
2. Send `/newbot`
3. Choose a name (e.g., "Jonas Clawdbot")
4. Choose a username (must end in `bot`, e.g., `jonas_clawdbot_bot`)
5. Copy the HTTP API token (format: `123456789:ABCdefGHI...`)

### 1.2 Get Your Chat ID

1. Start a chat with your new bot (send any message)
2. Open: `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates`
3. Find `"chat":{"id":123456789}` - that number is your chat ID

### 1.3 Store the Token

On the desktop machine:

```bash
mkdir -p ~/.secrets
echo "YOUR_TELEGRAM_TOKEN" > ~/.secrets/telegram-token
chmod 600 ~/.secrets/telegram-token
```

### Success Criteria

#### Manual Verification:
- [ ] Bot created and token saved to `~/.secrets/telegram-token`
- [ ] Chat ID noted for configuration
- [ ] File permissions are 600

---

## Phase 2: Flake Integration

### 2.1 Add Flake Input

**File**: `nix/flake.nix`

Add to inputs (after `xremap-flake`):

```nix
nix-clawdbot.url = "github:clawdbot/nix-clawdbot";
nix-clawdbot.inputs.nixpkgs.follows = "nixpkgs";
```

### 2.2 Pass Through Outputs

**File**: `nix/flake.nix`

Add `nix-clawdbot` to the outputs function parameters (line ~28):

```nix
outputs = {
  ...
  xremap-flake,
  nix-clawdbot,  # Add this
  ...
}:
```

### 2.3 Add to mkHost specialArgs

**File**: `nix/flake.nix`

In the `mkHost` function's `specialArgs` (around line 144), add:

```nix
specialArgs = {
  inherit
    self
    zen-browser
    walker
    nurPkgs
    xremap-flake
    nix-clawdbot  # Add this
    nixpkgs-xwayland
    ;
};
```

### Success Criteria

#### Automated Verification:
- [ ] Flake evaluates: `nix flake check nix/`
- [ ] Input resolves: `nix flake metadata nix/ | grep clawdbot`

---

## Phase 3: Home Manager Configuration

### 3.1 Forward to Home Manager extraSpecialArgs

**File**: `nix/modules/nixos/system.nix`

Add `nix-clawdbot` to function parameters (line ~7):

```nix
{
  config,
  pkgs,
  lib,
  ...
  xremap-flake,
  nix-clawdbot,  # Add this
  ...
}:
```

Add to `home-manager.extraSpecialArgs` (around line 171):

```nix
extraSpecialArgs = {
  inherit
    ...
    xremap-flake
    nix-clawdbot  # Add this
    ;
};
```

### 3.2 Create Clawdbot Module

**File**: `nix/home/nixos/clawdbot.nix` (new file)

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
      # Use Helium browser (ungoogled-chromium based, in PATH via system packages)
      browser.executablePath = "helium";
      # Workspace access - dotfiles and code directories
      agents.defaults.workspace = "~/code";  # Default workspace
      agents.defaults.allowedPaths = [
        "~/dotfiles"
        "~/code"
      ];
    };

    # coding-agent skill: run/resume Codex CLI, Claude Code, OpenCode, or Pi
    plugins = [
      { source = "github:clawdbot/skills?dir=skills/steipete/coding-agent"; }
    ];

    providers.telegram = {
      enable = true;
      botTokenFile = "~/.secrets/telegram-token";
      allowFrom = [ YOUR_CHAT_ID ];  # Replace with actual chat ID
    };

    # systemd user service (Linux)
    systemd.enable = true;
  };
}
```

### 3.3 Import Module (Desktop Only)

**File**: `nix/hosts/desktop/default.nix`

Add to the `home-manager.users.thrawny` block (around line 141):

```nix
home-manager.users.thrawny =
  { lib, nix-clawdbot, ... }:  # Add nix-clawdbot to args
  {
    imports = [ ../../home/nixos/clawdbot.nix ];  # Add this import

    # ... existing config
  };
```

### Success Criteria

#### Automated Verification:
- [ ] Config builds: `nixos-rebuild build --flake .#thrawny-desktop`
- [ ] No evaluation errors

---

## Phase 4: Deploy and Verify

### 4.1 Apply Configuration

On desktop:

```bash
cd ~/dotfiles/nix
sudo nixos-rebuild switch --flake .#thrawny-desktop
```

### 4.2 Verify Service

```bash
# Check service status
systemctl --user status clawdbot-gateway

# View logs
journalctl --user -u clawdbot-gateway -f
```

### 4.3 Test via Telegram

1. Send "hello" to your bot
2. Should receive a response from Clawdbot
3. Try: "open browser and go to github.com"

### Success Criteria

#### Automated Verification:
- [ ] Service active: `systemctl --user is-active clawdbot-gateway`

#### Manual Verification:
- [ ] Telegram "hello" receives response
- [ ] Browser command opens browser
- [ ] Logs show successful message processing

---

## Phase 5: Rollback (If Needed)

### 5.1 Quick Disable

Stop the service without removing config:

```bash
systemctl --user stop clawdbot-gateway
systemctl --user disable clawdbot-gateway
```

### 5.2 Full Removal

1. **Remove import** from `nix/hosts/desktop/default.nix`:
   - Remove `imports = [ ../../home/nixos/clawdbot.nix ];`
   - Remove `nix-clawdbot` from function args

2. **Delete module**: `rm nix/home/nixos/clawdbot.nix`

3. **Optionally remove flake input** (can leave for future use):
   - Remove from `flake.nix` inputs
   - Remove from outputs parameters
   - Remove from `mkHost` specialArgs
   - Remove from `system.nix` extraSpecialArgs

4. **Rebuild**:
   ```bash
   sudo nixos-rebuild switch --flake .#thrawny-desktop
   ```

5. **Clean up secrets** (optional):
   ```bash
   rm ~/.secrets/telegram-token
   ```

### Success Criteria

#### Automated Verification:
- [ ] Service gone: `systemctl --user status clawdbot-gateway` shows "not found"
- [ ] Config builds without clawdbot

---

## Testing Strategy

### Unit Tests
- Flake evaluation: `nix flake check`
- Build without switch: `nixos-rebuild build`

### Integration Tests
- Service starts and stays running for 60s
- Telegram message round-trip works

### Manual Testing Steps
1. Send "what time is it" - verify AI response
2. Send "take a screenshot" - verify peekaboo works
3. Send "open browser and go to news.ycombinator.com" - verify Helium launches
4. Send "resume my last codex session" - verify coding-agent skill works
5. Send nonsense - verify graceful handling

---

## References

- nix-clawdbot repo: https://github.com/clawdbot/nix-clawdbot
- Clawdbot docs: https://docs.clawd.bot
- Pattern reference: `nix/home/nixos/default.nix:17` (xremap integration)
- extraSpecialArgs pattern: `nix/modules/nixos/system.nix:170`
