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
  seedboxWorkspace = "/srv/agents/openclaw/workspaces/seedbox";
  stateDir = "${home}/.openclaw";
  uiSource = "${openclawPackage}/lib/openclaw/dist/control-ui";
  uiRoot = "/var/lib/openclaw-ui/${builtins.baseNameOf (toString openclawPackage)}";
  runtimePlugins = [
    "codex"
    "discord"
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
    models.providers.openai = {
      agentRuntime.id = "codex";
      # New Codex model IDs can precede OpenClaw's static route table. Declare
      # subscription transport rather than letting unknown IDs select API keys.
      api = "openai-chatgpt-responses";
      baseUrl = "https://chatgpt.com/backend-api/codex";
    };
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
      ownership = "explicit";
      defaults = {
        model = {
          primary = "openai/gpt-6-sol";
          fallbacks = [ ];
        };
        inherit workspace;
        skipBootstrap = true;
        timeoutSeconds = 900;
        thinkingDefault = "low";
        heartbeat = {
          every = "0m";
          agentId = "main";
        };
        systemAgent.agentId = "main";
        modelPolicy.allow = [
          "openai/gpt-6-sol"
          "openai/gpt-6-luna"
        ];
      };
      entries = {
        # Keep the existing workspace when adding a second agent; otherwise
        # multi-agent defaults derive an agent-id subdirectory.
        main.workspace = workspace;
        seedbox = {
          name = "Seedbox";
          workspace = seedboxWorkspace;
        };
      };
    };
    bindings = [
      {
        agentId = "seedbox";
        match = {
          channel = "telegram";
          accountId = "default";
          peer = {
            kind = "group";
            id = "-5176945403";
          };
        };
      }
      {
        agentId = "main";
        match = {
          channel = "telegram";
          accountId = "default";
        };
      }
      {
        agentId = "main";
        match = {
          channel = "discord";
          accountId = "default";
        };
      }
    ];
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
        memory-core = {
          subagent = {
            allowModelOverride = true;
            allowedModels = [ "openai/gpt-6-luna" ];
          };
          config.dreaming = {
            model = "openai/gpt-6-luna";
            timezone = "Europe/Stockholm";
          };
        };
      };
      allow = runtimePlugins;
    };
    skills.workshop.autonomous.mode = "off";
    channels = {
      telegram = {
        enabled = true;
        groupPolicy = "allowlist";
        groups."-5176945403" = {
          enabled = true;
          requireMention = true;
          allowFrom = [ "781443178" ];
        };
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
    seedboxWorkspace
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
