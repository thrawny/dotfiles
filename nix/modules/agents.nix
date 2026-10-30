{
  config,
  lib,
  pkgs,
  llm-agents,
  nix-openclaw,
  zmx,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  llmPkgs = llm-agents.packages.${system};
  openclawPkgs = nix-openclaw.packages.${system};
  # Codex claims reserved harness/command hooks, which require bundled origin.
  # Keep its SDK peer in this gateway so both use the same runtime registry.
  openclawPackage = openclawPkgs.openclaw-gateway.overrideAttrs (old: {
    installPhase =
      old.installPhase
      + "\n"
      + ''
        codex_root="$out/lib/openclaw/dist-runtime/extensions/codex"
        mkdir -p "$codex_root"
        cp -R ${openclawPkgs.openclaw-runtime-plugin-codex}/. "$codex_root/"
        chmod -R u+w "$codex_root"
        rm "$codex_root/node_modules/openclaw"
        ln -s ../../../.. "$codex_root/node_modules/openclaw"
      '';
  });
  openclawPluginPackages = map (id: openclawPkgs.${"openclaw-runtime-plugin-${id}"}) [
    "discord"
  ];
  zmxPkg = zmx.packages.${system}.zmx-main;
  openclaw = import ./openclaw.nix {
    inherit config lib pkgs;
    codexPackage = llmPkgs.codex;
    inherit openclawPackage openclawPluginPackages;
  };
  # Run administrative commands as the service user with the same config,
  # credentials and tools. Never source the systemd EnvironmentFile as shell code.
  openclawAdmin = pkgs.writeShellApplication {
    name = "openclaw-admin";
    runtimeInputs = [ pkgs.systemd ];
    text =
      let
        service = config.systemd.services.openclaw;
        envArgs = lib.mapAttrsToList (name: value: "--setenv=${name}=${value}") service.environment;
      in
      ''
        if [ "$EUID" -ne 0 ]; then
          echo "Run with sudo: sudo openclaw-admin <command>" >&2
          exit 1
        fi
        terminal_args=(--pipe)
        if [ -t 0 ] && [ -t 1 ]; then
          terminal_args=(--pty)
        fi
        exec systemd-run --quiet --wait --collect "''${terminal_args[@]}" \
          --property=User=openclaw --property=Group=openclaw \
          --property=WorkingDirectory=${lib.escapeShellArg openclaw.workspace} \
          --property=EnvironmentFile=/srv/agents/openclaw/env \
          ${lib.escapeShellArgs envArgs} \
          ${lib.getExe openclawPackage} "$@"
      '';
  };
  forgejoHost = "forgejo.${config.dotfiles.tailnetDomain}";
  forgejoUrl = "https://${forgejoHost}";
  commonPath = [
    llmPkgs.claude-code
    llmPkgs.codex
    llmPkgs.pi
    llmPkgs.agent-browser
    zmxPkg
    pkgs.bashInteractive
    pkgs.bun
    pkgs.coreutils
    pkgs.fd
    pkgs.forgejo-cli
    pkgs.gh
    pkgs.git
    pkgs.go
    pkgs.jq
    pkgs.nodejs
    pkgs.nix
    pkgs.pnpm_11
    pkgs.podman
    pkgs.python3
    pkgs.ripgrep
    pkgs.starship
    pkgs.uv
    pkgs.zsh
  ];

  mkAgentUser =
    {
      name,
      uid,
      description,
    }:
    {
      users.groups.${name} = { };
      users.users.${name} = {
        inherit uid description;
        isSystemUser = true;
        group = name;
        home = "/srv/agents/${name}/home";
        createHome = true;
        autoSubUidGidRange = true;
        linger = true;
        shell = pkgs.zsh;
      };
    };

  mkAgentService =
    {
      name,
      agentName ? name,
      uid,
      user ? agentName,
      package,
      command,
      execStartPre ? [ ],
      environmentFile ? "/srv/agents/${agentName}/env",
      extraEnvironment ? { },
      extraServiceConfig ? { },
    }:
    {
      systemd.services.${name} = {
        description = "${name} agent service";
        wantedBy = [ "multi-user.target" ];
        wants = [
          "linger-users.service"
          "network-online.target"
          "user@${toString uid}.service"
        ];
        after = [
          "network-online.target"
          "linger-users.service"
          "user@${toString uid}.service"
        ];
        path = [ package ] ++ commonPath;
        environment = {
          HOME = "/srv/agents/${agentName}/home";
          USER = user;
          LOGNAME = user;
          XDG_RUNTIME_DIR = "/run/user/${toString uid}";
          DOCKER_HOST = "unix:///run/user/${toString uid}/podman/podman.sock";
          FJ_FALLBACK_HOST = forgejoUrl;
        }
        // extraEnvironment;
        serviceConfig = {
          User = user;
          Group = user;
          WorkingDirectory = "/srv/agents/${agentName}/workspace";
          EnvironmentFile = "-${environmentFile}";
          ExecStart = command;
          Restart = "always";
          RestartSec = 10;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ReadWritePaths = [
            "/run/user/${toString uid}"
            "/srv/agents/${agentName}"
          ];
          TasksMax = 4096;
        }
        // extraServiceConfig
        // lib.optionalAttrs (execStartPre != [ ]) { ExecStartPre = execStartPre; };
      };
    };

  mkForgejoBootstrap =
    {
      agentName,
      botUser,
      botDisplayName,
      botEmail,
      uid,
      extraExports ? { },
      workspace ? "/srv/agents/${agentName}/workspace",
    }:
    let
      gitConfig = pkgs.writeText "${agentName}-gitconfig" ''
        [user]
            name = ${botDisplayName}
            email = ${botEmail}

        [credential "${forgejoUrl}"]
            helper = store
            username = ${botUser}

        [init]
            defaultBranch = main

        [push]
            default = simple

        [url "${forgejoUrl}/"]
            insteadOf = forgejo:
      '';

      forgejoGuide = pkgs.writeText "${agentName}-forgejo.md" ''
        # Forgejo

        Host: ${forgejoUrl}
        User: ${botUser}

        Git and fj auth are preconfigured from ~/.config/forgejo/token.

        Useful commands:

        - Create a repo for the current checkout: `fj repo create <repo> --private --remote forgejo`
        - Add a Forgejo remote manually: `git remote add forgejo forgejo:<owner>/<repo>.git`
        - Push a branch: `git push -u forgejo HEAD`
        - Create a PR from a branch: `fj pr create --repo <owner>/<repo> --head <branch> --base main --autofill`
        - Check auth: `fj whoami`
      '';
      zshExports = {
        DOCKER_HOST = "unix:///run/user/${toString uid}/podman/podman.sock";
        FJ_FALLBACK_HOST = forgejoUrl;
        XDG_RUNTIME_DIR = "/run/user/${toString uid}";
      }
      // extraExports;
      exportLines = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") zshExports
      );
      zshrc = pkgs.writeText "${agentName}-zshrc" ''
        export PATH=/run/current-system/sw/bin:$PATH
        export COLORTERM=truecolor
        ${exportLines}

        if [ -d ${lib.escapeShellArg workspace} ]; then
          cd ${lib.escapeShellArg workspace}
        fi

        eval "$(${lib.getExe pkgs.starship} init zsh)"
      '';
    in
    pkgs.writeShellApplication {
      name = "${agentName}-forgejo-bootstrap";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.jq
      ];
      text = ''
        set -euo pipefail

        agent_home="/srv/agents/${agentName}/home"
        workspace=${lib.escapeShellArg workspace}
        token_path="$agent_home/.config/forgejo/token"
        fj_keys_dir="$agent_home/.local/share/forgejo-cli"
        fj_keys_path="$fj_keys_dir/keys.json"
        git_credentials="$agent_home/.git-credentials"

        install -d -m 0750 -o ${agentName} -g ${agentName} "$agent_home"
        install -d -m 0750 -o ${agentName} -g ${agentName} "$workspace"
        install -d -m 0700 -o ${agentName} -g ${agentName} "$agent_home/.config"
        install -d -m 0700 -o ${agentName} -g ${agentName} "$agent_home/.config/forgejo"
        install -d -m 0700 -o ${agentName} -g ${agentName} "$fj_keys_dir"

        install -m 0600 -o ${agentName} -g ${agentName} ${gitConfig} "$agent_home/.gitconfig"
        install -m 0644 -o ${agentName} -g ${agentName} ${zshrc} "$agent_home/.zshrc"
        install -m 0644 -o ${agentName} -g ${agentName} ${forgejoGuide} "$workspace/FORGEJO.md"

        if [ -r "$token_path" ]; then
          token="$(tr -d '\r\n' < "$token_path")"
          if [ -n "$token" ]; then
            keys_tmp="$(mktemp)"
            jq -n \
              --arg host ${lib.escapeShellArg forgejoHost} \
              --arg name ${lib.escapeShellArg botUser} \
              --arg token "$token" \
              '{hosts: {($host): {type: "Application", name: $name, token: $token}}, aliases: {}, default_ssh: []}' \
              > "$keys_tmp"
            install -m 0600 -o ${agentName} -g ${agentName} "$keys_tmp" "$fj_keys_path"
            rm -f "$keys_tmp"

            credentials_tmp="$(mktemp)"
            encoded_user="$(jq -rn --arg value ${lib.escapeShellArg botUser} '$value | @uri')"
            encoded_token="$(jq -rn --arg value "$token" '$value | @uri')"
            printf 'https://%s:%s@%s\n' "$encoded_user" "$encoded_token" ${lib.escapeShellArg forgejoHost} > "$credentials_tmp"
            install -m 0600 -o ${agentName} -g ${agentName} "$credentials_tmp" "$git_credentials"
            rm -f "$credentials_tmp"
          fi
        fi
      '';
    };
in
lib.mkMerge [
  {
    users.manageLingering = true;
    systemd.services.openclaw = {
      # Rootless Podman needs the setuid newuidmap/newgidmap wrappers.
      path = [ "/run/wrappers" ];
      restartTriggers = [ openclaw.configFile ];
      after = [
        "systemd-tmpfiles-setup.service"
        "systemd-tmpfiles-resetup.service"
      ];
    };

    system.build.openclaw-runtime = openclawPackage;
    system.build.openclaw-check =
      pkgs.runCommand "openclaw-config-check"
        {
          nativeBuildInputs = [
            openclawPackage
            pkgs.jq
          ];
        }
        ''
          export HOME="$TMPDIR/home"
          mkdir -p "$HOME"
          export OPENCLAW_NIX_MODE=1
          # Runtime group identifiers remain outside the public Nix store config.
          export OPENCLAW_SHARED_GROUP_ID=-1000000000000
          export OPENCLAW_TELEGRAM_EXEC_APPROVER=1000000000
          export OPENCLAW_INCLUDE_ROOTS="$TMPDIR"
          printf '%s' '{}' > "$TMPDIR/shared-groups.json"
          jq --arg include "$TMPDIR/shared-groups.json" \
            '.channels.telegram.groups."$include" = $include' \
            ${openclaw.configFile} > "$TMPDIR/openclaw.json"
          export OPENCLAW_CONFIG_PATH="$TMPDIR/openclaw.json"
          export OPENCLAW_STATE_DIR="$HOME/.openclaw"
          test -s ${openclaw.uiSource}/index.html
          for plugin_dir in $(jq -r '.plugins.load.paths[]' ${openclaw.configFile}); do
            test -s "$plugin_dir/openclaw.plugin.json"
            jq -e 'has("id")' "$plugin_dir/openclaw.plugin.json"
          done
          for plugin_id in codex memory-core openai telegram; do
            test -s ${openclawPackage}/lib/openclaw/dist-runtime/extensions/$plugin_id/openclaw.plugin.json
          done
          openclaw config validate --json > "$out"
          # Discovery warnings can concern unused bundled plugins. Keep them
          # visible; the live health check rejects active plugin failures.
          jq -r '.warnings[]? | "Config warning: \(.message)"' "$out" >&2
          jq -e '.valid == true' "$out"
          if openclaw config set gateway.port 19999 > "$TMPDIR/write-error" 2>&1; then
            echo "Nix mode unexpectedly allowed a config write" >&2
            exit 1
          fi
          grep -q 'managed by Nix' "$TMPDIR/write-error"
          jq -e '
            .gateway.auth.token.source == "env" and
            .channels.discord.token.source == "file" and
            .channels.telegram.botToken.source == "env" and
            .models.providers.openai.agentRuntime.id == "codex" and
            .models.providers.openai.api == "openai-chatgpt-responses" and
            .models.providers.openai.baseUrl == "https://chatgpt.com/backend-api/codex" and
            .models.providers.openai.models[0].id == "gpt-6.1-sol" and
            .agents.defaults.model.primary == "openai/gpt-6.1-sol" and
            .agents.defaults.model.fallbacks == [] and
            .agents.defaults.thinkingDefault == "low" and
            .agents.defaults.heartbeat.every == "0m" and
            .agents.defaults.modelPolicy.allow == ["openai/gpt-6.1-sol", "openai/gpt-6-sol", "openai/gpt-6-luna"] and
            .plugins.entries["memory-core"].config.dreaming.model == "openai/gpt-6-luna" and
            .plugins.entries["memory-core"].subagent.allowedModels == ["openai/gpt-6-luna"] and
            .skills.workshop.autonomous.mode == "off" and
            .agents.entries.main.workspace == "${openclaw.workspace}" and
            .agents.entries.seedbox.workspace == "${openclaw.seedboxWorkspace}" and
            .agents.defaults.systemAgent.agentId == "main" and
            .channels.telegram.groups["-5176945403"].allowFrom == ["781443178", "718852556"] and
            .channels.telegram.groups["-5176945403"].requireMention == true and
            ([.bindings[] | select(.agentId == "seedbox")] | length) == 1 and
            ([.bindings[] | select(.agentId == "seedbox")][0].match.peer.id == "-5176945403") and
            .plugins.allow == ["codex", "discord", "memory-core", "openai", "telegram"] and
            (.plugins.load.paths | length) == 1
          ' ${openclaw.configFile}
        '';

    virtualisation = {
      containers.enable = true;
      podman = {
        enable = true;
        dockerCompat = true;
        defaultNetwork.settings.dns_enabled = true;
      };
    };

    environment.systemPackages = [
      openclawPackage
      openclawAdmin
      zmxPkg
      pkgs.podman-compose
    ]
    ++ commonPath;

    systemd.tmpfiles.rules = [
      "d /srv/agents 0755 root root -"
      "d /srv/agents/openclaw 0750 openclaw openclaw -"
      "d /srv/agents/openclaw/home 0750 openclaw openclaw -"
      # Bootstrap's nested mkdir previously left these ancestors owned by root,
      # preventing rootless Podman from creating its storage directory.
      "d /srv/agents/openclaw/home/.local 0750 openclaw openclaw -"
      "d /srv/agents/openclaw/home/.local/share 0750 openclaw openclaw -"
      "d /srv/agents/openclaw/home/.openclaw 0750 openclaw openclaw -"
      "d /srv/agents/openclaw/home/.openclaw/secrets 0700 openclaw openclaw -"
      "d /srv/agents/openclaw/workspace 0750 openclaw openclaw -"
      "d /srv/agents/openclaw/workspaces 0750 openclaw openclaw -"
      "d ${openclaw.seedboxWorkspace} 0750 openclaw openclaw -"
      "d ${openclaw.sharedWorkspace} 0750 openclaw openclaw -"
      "L+ ${openclaw.stateDir}/openclaw.json - - - - ${openclaw.configFile}"
      "d /var/lib/openclaw-ui 0755 root root -"
      "C ${openclaw.uiRoot} - root root - ${openclaw.uiSource}"
    ];

    services.tailscaleServe.services = {
      openclaw = {
        target = "http://127.0.0.1:18789";
        wants = [ "openclaw.service" ];
        after = [ "openclaw.service" ];
      };
    };
  }

  (mkAgentUser {
    name = "openclaw";
    uid = 3101;
    description = "OpenClaw agent service";
  })

  (mkAgentService {
    name = "openclaw";
    uid = 3101;
    package = openclawPackage;
    command = "${openclawPackage}/bin/openclaw gateway run";
    extraEnvironment = openclaw.environment;
    extraServiceConfig = {
      UMask = "0077";
      TimeoutStopSec = 120;
    };
    execStartPre = [
      "+${
        mkForgejoBootstrap {
          agentName = "openclaw";
          botUser = "gestral-bot";
          botDisplayName = "Gestral Vendor";
          botEmail = "gestral-bot@obelisk.local";
          uid = 3101;
          extraExports = openclaw.environment;
          inherit (openclaw) workspace;
        }
      }/bin/openclaw-forgejo-bootstrap"
    ];
  })

]
