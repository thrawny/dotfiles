{
  config,
  lib,
  pkgs,
  llm-agents,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  llmPkgs = llm-agents.packages.${system};
  openclaw = import ./openclaw.nix { inherit config lib pkgs; };
  hermes = import ./hermes.nix { inherit config lib pkgs; };
  forgejoHost = "forgejo.${config.dotfiles.tailnetDomain}";
  forgejoUrl = "https://${forgejoHost}";
  commonPath = [
    llmPkgs.claude-code
    llmPkgs.codex
    llmPkgs.pi
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
    pkgs.pnpm
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

    virtualisation = {
      containers.enable = true;
      podman = {
        enable = true;
        dockerCompat = true;
        defaultNetwork.settings.dns_enabled = true;
      };
    };

    environment.systemPackages = [
      llmPkgs.hermes-agent
      llmPkgs.openclaw
      pkgs.podman-compose
    ]
    ++ commonPath;

    systemd.tmpfiles.rules = [
      "d /srv/agents 0755 root root -"
      "d /srv/agents/openclaw 0750 openclaw openclaw -"
      "d /srv/agents/openclaw/home 0750 openclaw openclaw -"
      "d /srv/agents/openclaw/home/.openclaw 0750 openclaw openclaw -"
      "d /srv/agents/openclaw/home/.openclaw/secrets 0700 openclaw openclaw -"
      "d /srv/agents/openclaw/workspace 0750 openclaw openclaw -"
      "d /srv/agents/hermes 0750 hermes hermes -"
      "d /srv/agents/hermes/home 0750 hermes hermes -"
      "d /srv/agents/hermes/workspace 0750 hermes hermes -"
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

  (mkAgentUser {
    name = "hermes";
    uid = 3102;
    description = "Hermes agent service";
  })

  (mkAgentService {
    name = "openclaw";
    uid = 3101;
    package = llmPkgs.openclaw;
    command = "${llmPkgs.openclaw}/bin/openclaw gateway run --bind loopback --port 18789 --tailscale off --allow-unconfigured --force";
    execStartPre = [
      "+${
        mkForgejoBootstrap {
          agentName = "openclaw";
          botUser = "gestral-bot";
          botDisplayName = "Gestral Vendor";
          botEmail = "gestral-bot@obelisk.local";
          uid = 3101;
          inherit (openclaw) workspace;
        }
      }/bin/openclaw-forgejo-bootstrap"
      "+${openclaw.prepareConfig}/bin/openclaw-prepare-config"
    ];
  })

  (mkAgentService {
    name = "hermes";
    uid = 3102;
    package = llmPkgs.hermes-agent;
    command = "${llmPkgs.hermes-agent}/bin/hermes gateway run --replace --accept-hooks";
    environmentFile = hermes.envFile;
    extraEnvironment.HERMES_HOME = "${hermes.home}/.hermes";
    execStartPre = [
      "+${
        mkForgejoBootstrap {
          agentName = "hermes";
          botUser = "maelle-bot";
          botDisplayName = "Maelle";
          botEmail = "maelle-bot@obelisk.local";
          uid = 3102;
          extraExports.HERMES_HOME = "${hermes.home}/.hermes";
          inherit (hermes) workspace;
        }
      }/bin/hermes-forgejo-bootstrap"
      "+${hermes.prepareConfig}/bin/hermes-prepare-config"
    ];
    extraServiceConfig.TimeoutStopSec = 240;
  })
]
