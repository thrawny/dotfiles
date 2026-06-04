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
  commonPath = [
    llmPkgs.claude-code
    llmPkgs.codex
    llmPkgs.pi
    pkgs.bashInteractive
    pkgs.bun
    pkgs.coreutils
    pkgs.fd
    pkgs.gh
    pkgs.git
    pkgs.go
    pkgs.jq
    pkgs.nodejs
    pkgs.pnpm
    pkgs.podman
    pkgs.python3
    pkgs.ripgrep
    pkgs.uv
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
        };
        serviceConfig = {
          User = user;
          Group = user;
          WorkingDirectory = "/srv/agents/${agentName}/workspace";
          EnvironmentFile = "-/srv/agents/${agentName}/env";
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
        // lib.optionalAttrs (execStartPre != [ ]) { ExecStartPre = execStartPre; };
      };
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

      hermes = {
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
    execStartPre = [ "+${openclaw.prepareConfig}/bin/openclaw-prepare-config" ];
  })

  (mkAgentService {
    name = "hermes";
    uid = 3102;
    package = llmPkgs.hermes-agent;
    command = "${llmPkgs.hermes-agent}/bin/hermes gateway run --replace --accept-hooks";
  })

  (mkAgentService {
    name = "hermes-dashboard";
    agentName = "hermes";
    uid = 3102;
    user = "hermes";
    package = llmPkgs.hermes-agent;
    command = "${llmPkgs.hermes-agent}/bin/hermes dashboard --host 127.0.0.1 --port 9119 --no-open --skip-build";
  })
]
