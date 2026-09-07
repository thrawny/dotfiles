{
  codexPackage,
  config,
  lib,
  openclawPackage,
  pkgs,
}:
let
  json = pkgs.formats.json { };
  home = "/srv/agents/openclaw/home";
  workspace = "/srv/agents/openclaw/workspace";
  stateDir = "${home}/.openclaw";
  uiSource = "${openclawPackage}/lib/openclaw/dist/control-ui";
  uiRoot = "/var/lib/openclaw-ui/${builtins.baseNameOf (toString openclawPackage)}";
  runtimePlugins = [
    "codex"
    "discord"
    "duckduckgo"
    "openai"
    "telegram"
  ];

  openclawConfig = {
    "$schema" = "https://docs.openclaw.ai/schema/openclaw.json";
    gateway = {
      mode = "local";
      bind = "loopback";
      port = 18789;
      controlUi = {
        enabled = true;
        # Serve the prebuilt UI without runtime asset retention. Custom roots
        # reject Nix store hardlinks, so tmpfiles materializes a root-owned copy.
        root = uiRoot;
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
      tailscale.mode = "off";
      auth = {
        mode = "token";
        token = {
          source = "env";
          provider = "default";
          id = "OPENCLAW_GATEWAY_AUTH_TOKEN";
        };
      };
      trustedProxies = [
        "127.0.0.1"
        "::1"
      ];
    };
    # The canonical openai/* route uses the Codex subscription/runtime here,
    # not Platform API-key billing. Fail closed instead of falling back to the
    # embedded OpenClaw runtime.
    models.providers.openai.agentRuntime.id = "codex";
    tools = {
      profile = "full";
      fs.workspaceOnly = true;
      exec.applyPatch.workspaceOnly = true;
      web.search = {
        enabled = true;
        openaiCodex = {
          enabled = true;
          mode = "cached";
        };
      };
    };
    agents = {
      defaults = {
        model = {
          primary = "openai/gpt-5.6-sol";
          fallbacks = [ ];
        };
        inherit workspace;
        skipBootstrap = true;
        timeoutSeconds = 900;
        thinkingDefault = "low";
        models."openai/gpt-5.6-sol" = { };
      };
      entries.main = { };
    };
    plugins = {
      entries = {
        openai.enabled = true;
        codex = {
          enabled = true;
          config.appServer = {
            command = lib.getExe codexPackage;
            homeScope = "user";
          };
        };
        discord.enabled = true;
        telegram.enabled = true;
        canvas.enabled = false;
      };
      allow = runtimePlugins;
      # Use the host's compiled runtime tree so plugins retain bundled trust.
      # Source/dist paths are classified as external and lose channel-state APIs.
      # Explicit paths also avoid relying on the legacy SQLite discovery setting.
      load.paths = map (
        id: "${openclawPackage}/lib/openclaw/dist-runtime/extensions/${id}"
      ) runtimePlugins;
    };
    messages = {
      groupChat.visibleReplies = "automatic";
      visibleReplies = "automatic";
    };
    channels = {
      telegram = {
        enabled = true;
        botToken = {
          source = "env";
          provider = "default";
          id = "TELEGRAM_BOT_TOKEN";
        };
      };
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
              requireMention = true;
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
            "1512036786870685696" = {
              enabled = true;
              requireMention = false;
              users = [ "231780291440672768" ];
              includeThreadStarter = true;
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
      path = "${stateDir}/secrets/discord.json";
      mode = "json";
    };
    commands = {
      ownerAllowFrom = [ "discord:231780291440672768" ];
      restart = false;
    };
  };

  configFile = json.generate "openclaw.json" openclawConfig;
in
{
  inherit
    home
    workspace
    stateDir
    uiSource
    uiRoot
    configFile
    ;

  environment = {
    OPENCLAW_NIX_MODE = "1";
    OPENCLAW_STATE_DIR = stateDir;
    # 2026.8.2's recovery path bypasses the Nix write guard and can replace a
    # symlink with stale config. Read the store path directly, accepting its
    # harmless warning when it tries to write a sibling .last-good file.
    OPENCLAW_CONFIG_PATH = toString configFile;
  };
}
