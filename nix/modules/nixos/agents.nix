{
  config,
  lib,
  pkgs,
  llm-agents,
  zmx,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  llmPkgs = llm-agents.packages.${system};
  zmxPkg = zmx.packages.${system}.zmx-main;
  openclaw = import ./openclaw.nix { inherit config lib pkgs; };
  hermes = import ./hermes.nix { inherit config lib pkgs; };
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

  mkHermesDashboardAuthBootstrap =
    let
      passwordHashScript = pkgs.writeText "hermes-dashboard-password-hash.py" ''
        import base64
        import hashlib
        import secrets

        password = secrets.token_urlsafe(24)
        n = 2**14
        r = 8
        p = 1
        salt = secrets.token_bytes(16)
        digest = hashlib.scrypt(
            password.encode("utf-8"),
            salt=salt,
            n=n,
            r=r,
            p=p,
            dklen=32,
            maxmem=0,
        )
        print(password)
        print(
            "scrypt$"
            + str(n)
            + "$"
            + str(r)
            + "$"
            + str(p)
            + "$"
            + base64.b64encode(salt).decode()
            + "$"
            + base64.b64encode(digest).decode()
        )
      '';
    in
    pkgs.writeShellApplication {
      name = "hermes-dashboard-auth-bootstrap";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.python3
      ];
      text = ''
        set -euo pipefail

        hermes_dir=${lib.escapeShellArg "${hermes.home}/.hermes"}
        env_path=${lib.escapeShellArg hermes.envFile}
        password_path="$hermes_dir/dashboard-password"

        install -d -m 0750 -o hermes -g hermes "$hermes_dir"
        if [ ! -e "$env_path" ]; then
          install -m 0600 -o hermes -g hermes /dev/null "$env_path"
        fi

        set_env_var() {
          key="$1"
          value="$2"
          tmp="$(mktemp)"
          grep -v "^$key=" "$env_path" > "$tmp" || true
          printf '%s=%s\n' "$key" "$value" >> "$tmp"
          install -m 0600 -o hermes -g hermes "$tmp" "$env_path"
          rm -f "$tmp"
        }

        ensure_env_var() {
          key="$1"
          value="$2"
          if ! grep -q "^$key=" "$env_path"; then
            set_env_var "$key" "$value"
          fi
        }

        ensure_env_var HERMES_DASHBOARD_BASIC_AUTH_USERNAME admin

        needs_password=false
        if ! grep -Eq '^(HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH|HERMES_DASHBOARD_BASIC_AUTH_PASSWORD)=' "$env_path"; then
          needs_password=true
        elif [ ! -f "$password_path" ] && ! grep -q '^HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=' "$env_path"; then
          needs_password=true
        fi

        if [ "$needs_password" = true ]; then
          mapfile -t generated < <(python3 ${passwordHashScript})
          password="''${generated[0]}"
          password_hash="''${generated[1]}"

          set_env_var HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH "$password_hash"

          password_tmp="$(mktemp)"
          printf '%s\n' "$password" > "$password_tmp"
          install -m 0600 -o root -g root "$password_tmp" "$password_path"
          rm -f "$password_tmp"
        fi

        if ! grep -q '^HERMES_DASHBOARD_BASIC_AUTH_SECRET=' "$env_path"; then
          secret="$(python3 - <<'PY'
        import secrets
        print(secrets.token_urlsafe(48))
        PY
        )"
          set_env_var HERMES_DASHBOARD_BASIC_AUTH_SECRET "$secret"
        fi

        chown hermes:hermes "$env_path"
        chmod 0600 "$env_path"
      '';
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

    virtualisation = {
      containers.enable = true;
      podman = {
        enable = true;
        dockerCompat = true;
        defaultNetwork.settings.dns_enabled = true;
      };
    };

    environment.systemPackages = [
      llmPkgs.openclaw
      zmxPkg
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
    ];

    services.tailscaleServe.services = {
      openclaw = {
        target = "http://127.0.0.1:18789";
        wants = [ "openclaw.service" ];
        after = [ "openclaw.service" ];
      };
      hermes-dashboard = {
        serviceName = "svc:hermes";
        target = "http://127.0.0.1:9119";
        wants = [ "hermes-dashboard.service" ];
        after = [ "hermes-dashboard.service" ];
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

  {
    services.hermes-agent = {
      enable = true;
      createUser = false;
      user = "hermes";
      group = "hermes";
      stateDir = hermes.home;
      workingDirectory = hermes.workspace;
      addToSystemPackages = true;
      extraArgs = [
        "run"
        "--replace"
        "--accept-hooks"
      ];
      extraDependencyGroups = [ "messaging" ];
      extraPackages = commonPath;
      restartSec = 10;
      settings = {
        plugins.enabled = [ "discord" ];

        model = {
          provider = "openai-codex";
          default = "gpt-5.5";
        };

        terminal = {
          backend = "local";
          working_dir = hermes.workspace;
          cwd = hermes.workspace;
        };

        agent.restart_drain_timeout = 60;

        discord = {
          require_mention = true;
          thread_require_mention = false;
          auto_thread = true;
          reactions = true;
          allowed_channels = [
            "777231848123924561"
            "1510629338264113252"
            "1512036755673448579"
          ];
          free_response_channels = [ "1512036755673448579" ];
          history_backfill = true;
          history_backfill_limit = 50;
          allow_mentions = {
            everyone = false;
            roles = false;
            users = true;
            replied_user = true;
          };
        };
      };
    };

    systemd.services.hermes-dashboard = {
      description = "Hermes Agent web dashboard";
      wantedBy = [ "multi-user.target" ];
      wants = [
        "network-online.target"
        "hermes-agent.service"
      ];
      after = [
        "network-online.target"
        "hermes-agent.service"
      ];
      path = [
        config.services.hermes-agent.package
        pkgs.bash
        pkgs.coreutils
      ]
      ++ commonPath;
      environment = {
        HOME = hermes.home;
        HERMES_HOME = "${hermes.home}/.hermes";
        HERMES_MANAGED = "true";
        USER = "hermes";
        LOGNAME = "hermes";
        XDG_RUNTIME_DIR = "/run/user/3102";
      };
      serviceConfig = {
        User = "hermes";
        Group = "hermes";
        WorkingDirectory = hermes.workspace;
        ExecStartPre = "+${mkHermesDashboardAuthBootstrap}/bin/hermes-dashboard-auth-bootstrap";
        ExecStart = "${config.services.hermes-agent.package}/bin/hermes dashboard --no-open --host 0.0.0.0 --port 9119 --skip-build";
        Restart = "always";
        RestartSec = 10;
        UMask = "0007";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = false;
        ReadWritePaths = [
          hermes.home
          hermes.workspace
          "/run/user/3102"
        ];
        PrivateTmp = true;
        TasksMax = 1024;
      };
    };

    systemd.services.hermes-agent = {
      wants = [
        "linger-users.service"
        "user@3102.service"
      ];
      after = [
        "linger-users.service"
        "user@3102.service"
      ];
      environment = {
        USER = "hermes";
        LOGNAME = "hermes";
        XDG_RUNTIME_DIR = "/run/user/3102";
        DOCKER_HOST = "unix:///run/user/3102/podman/podman.sock";
        FJ_FALLBACK_HOST = forgejoUrl;
      };
      serviceConfig = {
        ExecStartPre = "+${
          mkForgejoBootstrap {
            agentName = "hermes";
            botUser = "maelle-bot";
            botDisplayName = "Maelle";
            botEmail = "maelle-bot@obelisk.local";
            uid = 3102;
            extraExports.HERMES_HOME = "${hermes.home}/.hermes";
            inherit (hermes) workspace;
          }
        }/bin/hermes-forgejo-bootstrap";
        ReadWritePaths = lib.mkAfter [ "/run/user/3102" ];
        UnsetEnvironment = [ "MESSAGING_CWD" ];
        TasksMax = 4096;
        TimeoutStopSec = 240;
      };
    };
  }
]
