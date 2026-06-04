{
  config,
  lib,
  pkgs,
}:
let
  json = pkgs.formats.json { };
  home = "/srv/agents/openclaw/home";
  workspace = "/srv/agents/openclaw/workspace";

  openclawConfig = {
    "$schema" = "https://docs.openclaw.ai/schema/openclaw.json";
    gateway = {
      mode = "local";
      bind = "loopback";
      port = 18789;
      controlUi = {
        enabled = true;
        allowedOrigins = [
          "http://localhost:18789"
          "https://localhost:18789"
          "https://openclaw.${config.dotfiles.tailnetDomain}"
        ];
      };
      http.endpoints = {
        chatCompletions.enabled = false;
        responses.enabled = false;
      };
      tailscale = {
        mode = "off";
        resetOnExit = false;
      };
      channelHealthCheckMinutes = 0;
      trustedProxies = [
        "127.0.0.1"
        "::1"
      ];
    };
    canvasHost.enabled = false;
    tools = {
      web.search = {
        enabled = true;
        openaiCodex = {
          enabled = true;
          mode = "cached";
        };
      };
      allow = [ "group:web" ];
    };
    agents = {
      defaults = {
        model = {
          primary = "openai/gpt-5.5";
          fallbacks = [ ];
        };
        inherit workspace;
        skipBootstrap = true;
        timeoutSeconds = 900;
        thinkingDefault = "low";
        models = {
          "openai/gpt-5.5" = { };
          "openai-codex/gpt-5.5" = { };
        };
      };
      list = [
        {
          id = "main";
          default = true;
          model = {
            primary = "openai/gpt-5.5";
            fallbacks = [ ];
          };
          inherit workspace;
        }
      ];
    };
    plugins = {
      entries = {
        openai.enabled = true;
        codex.enabled = true;
        discord.enabled = true;
      };
      allow = [
        "codex"
        "discord"
        "duckduckgo"
        "openai"
        "telegram"
      ];
      bundledDiscovery = "compat";
    };
    messages = {
      groupChat.visibleReplies = "automatic";
      visibleReplies = "automatic";
      removeAckAfterReply = true;
    };
    auth.profiles."openai-codex:jonas@lergell.se" = {
      provider = "openai-codex";
      mode = "oauth";
    };
    channels = {
      telegram.enabled = true;
      discord = {
        enabled = true;
        token = {
          source = "file";
          provider = "discord";
          id = "/DISCORD_BOT_TOKEN";
        };
        dmPolicy = "allowlist";
        allowFrom = [ "231780291440672768" ];
        groupPolicy = "allowlist";
        guilds."777231847595573249" = {
          requireMention = false;
          users = [ "231780291440672768" ];
          channels = {
            "777231848123924561" = {
              enabled = true;
              requireMention = false;
              users = [ "231780291440672768" ];
            };
            "1510629338264113252" = {
              enabled = true;
              requireMention = true;
              users = [ "231780291440672768" ];
              includeThreadStarter = true;
              autoThread = true;
              autoThreadName = "message";
              autoArchiveDuration = 1440;
            };
            "*" = {
              enabled = true;
              requireMention = true;
              users = [ "231780291440672768" ];
              includeThreadStarter = true;
            };
          };
        };
        thread.inheritParent = true;
        streaming.mode = "partial";
      };
    };
    secrets.providers.discord = {
      source = "file";
      path = "${home}/.openclaw/secrets/discord.json";
      mode = "json";
    };
    commands = {
      ownerAllowFrom = [ "discord:231780291440672768" ];
      restart = false;
    };
  };

  openclawConfigFile = json.generate "openclaw.json" openclawConfig;
in
{
  inherit home workspace;

  prepareConfig = pkgs.writeShellApplication {
    name = "openclaw-prepare-config";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      set -euo pipefail

      openclaw_home=${lib.escapeShellArg home}
      config_path="$openclaw_home/.openclaw/openclaw.json"
      secrets_dir="$openclaw_home/.openclaw/secrets"
      discord_secret="$secrets_dir/discord.json"

      install -d -m 0750 -o openclaw -g openclaw "$openclaw_home/.openclaw"
      install -d -m 0700 -o openclaw -g openclaw "$secrets_dir"

      config_tmp="$(mktemp)"
      cp ${openclawConfigFile} "$config_tmp"

      update_config() {
        next_tmp="$(mktemp)"
        jq "$1" "$config_tmp" > "$next_tmp"
        mv "$next_tmp" "$config_tmp"
      }

      if [ -n "''${OPENCLAW_GATEWAY_AUTH_TOKEN:-}" ]; then
        next_tmp="$(mktemp)"
        jq --arg token "$OPENCLAW_GATEWAY_AUTH_TOKEN" \
          '.gateway.auth = {mode: "token", token: $token}' \
          "$config_tmp" > "$next_tmp"
        mv "$next_tmp" "$config_tmp"
      fi

      if [ -z "''${DISCORD_BOT_TOKEN:-}" ] && [ ! -r "$discord_secret" ]; then
        update_config '
          .channels.discord.enabled = false
          | del(.channels.discord.token)
          | .plugins.entries.discord.enabled = false
          | .plugins.allow |= map(select(. != "discord"))
        '
      fi

      if [ -z "''${TELEGRAM_BOT_TOKEN:-}" ]; then
        update_config '
          .channels.telegram.enabled = false
          | .plugins.allow |= map(select(. != "telegram"))
        '
      fi

      install -m 0600 -o openclaw -g openclaw "$config_tmp" "$config_path"
      rm -f "$config_tmp"

      if [ -n "''${DISCORD_BOT_TOKEN:-}" ]; then
        secret_tmp="$(mktemp)"
        jq -n --arg token "$DISCORD_BOT_TOKEN" \
          '{DISCORD_BOT_TOKEN: $token}' > "$secret_tmp"
        install -m 0600 -o openclaw -g openclaw "$secret_tmp" "$discord_secret"
        rm -f "$secret_tmp"
      fi
    '';
  };
}
