{
  agentAssets,
  config,
  lib,
  pkgs,
  llm-agents,
  t3code,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  llmPkgs = llm-agents.packages.${system};

  uid = 3103;
  home = "/srv/t3code";
  codexHome = "${home}/.codex";
  state = "${home}/.t3code";
  repos = "${home}/repos";
  port = 3773;
  forgejoHost = "forgejo.${config.dotfiles.tailnetDomain}";
  forgejoUrl = "https://${forgejoHost}";
  forgejoUser = "thrawny";

  codexConfig = pkgs.runCommand "t3code-codex-config.toml" { } ''
    cat ${lib.escapeShellArg (toString agentAssets.codexFiles.config)} > "$out"
    cat >> "$out" <<'EOF'

    [projects."/srv/t3code/repos"]
    trust_level = "trusted"
    EOF
  '';

  codexSkills = agentAssets.skillEntriesFor "codex";
  codexSkillLinks = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: skill: ''
      link_store_path ${lib.escapeShellArg "${codexHome}/skills/${name}"} ${lib.escapeShellArg (toString skill.source)}
    '') codexSkills
  );

  package = pkgs.stdenv.mkDerivation (finalAttrs: {
    pname = "t3code";
    version = "main-${lib.substring 0 7 (t3code.rev or "unknown")}";
    src = t3code;

    pnpmDeps = pkgs.fetchPnpmDeps {
      inherit (finalAttrs) pname version src;
      fetcherVersion = 3;
      hash = "sha256-5zNPGij5DNJv42B0vaKQ2PHrKFVLxTOjJYOfAkCujqI=";
    };

    nativeBuildInputs = [
      pkgs.gcc
      pkgs.git
      pkgs.gnumake
      pkgs.node-gyp
      pkgs.nodejs
      pkgs.pnpm
      pkgs.pnpmConfigHook
      pkgs.python3
      pkgs.makeWrapper
    ];

    SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

    buildPhase = ''
      runHook preBuild

      pushd node_modules/.pnpm/node-pty@1.1.0/node_modules/node-pty
      node scripts/prebuild.js || node-gyp rebuild --nodedir=${pkgs.nodejs}
      node scripts/post-install.js
      test -f build/Release/pty.node
      popd

      pnpm exec vp config
      pnpm --filter @t3tools/web run build
      node apps/server/scripts/cli.ts build
      test -f apps/server/dist/bin.mjs
      test -f apps/server/dist/client/index.html

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      install -d "$out/lib/t3code"
      cp -R apps/server/dist "$out/lib/t3code/dist"
      cp -R apps packages scripts oxlint-plugin-t3code "$out/lib/t3code/"
      cp -R node_modules "$out/lib/t3code/node_modules"
      printf '{"type":"module"}\n' > "$out/lib/t3code/package.json"

      makeWrapper ${lib.getExe pkgs.nodejs} "$out/bin/t3" \
        --add-flags "$out/lib/t3code/apps/server/dist/bin.mjs" \
        --prefix PATH : ${
          lib.makeBinPath [
            llmPkgs.codex
            pkgs.git
            pkgs.nodejs
          ]
        }

      runHook postInstall
    '';

    meta.mainProgram = "t3";
  });

  codexWithDirenv = pkgs.writeShellApplication {
    name = "t3code-codex";
    runtimeInputs = [
      pkgs.direnv
      llmPkgs.codex
    ];
    text = ''
      set -euo pipefail

      export DIRENV_LOG_FORMAT=
      exec direnv exec "$PWD" ${lib.getExe llmPkgs.codex} "$@"
    '';
  };

  serverSettings = pkgs.writeText "t3code-settings.json" (
    builtins.toJSON {
      providers = {
        codex = {
          binaryPath = lib.getExe codexWithDirenv;
          homePath = codexHome;
        };
        claudeAgent.enabled = false;
        cursor.enabled = false;
        opencode.enabled = false;
        pi.enabled = false;
      };
      textGenerationModelSelection = {
        instanceId = "codex";
        model = "gpt-5.5";
      };
    }
  );

  gitConfig = pkgs.writeText "t3code-gitconfig" ''
    [user]
        name = Jonas Lergell
        email = jonas@lergell.se

    [credential "${forgejoUrl}"]
        helper = store
        username = ${forgejoUser}

    [init]
        defaultBranch = main

    [push]
        default = simple

    [url "${forgejoUrl}/"]
        insteadOf = forgejo:
  '';

  forgejoGuide = pkgs.writeText "t3code-forgejo.md" ''
    # Forgejo

    Host: ${forgejoUrl}
    User: ${forgejoUser}

    Git and fj auth are preconfigured from ~/.config/forgejo/token.

    Useful commands:

    - Add a Forgejo remote manually: `git remote add forgejo forgejo:<owner>/<repo>.git`
    - Push a branch: `git push -u forgejo HEAD`
    - Create a repo: `fj repo create <repo> --private`
    - Create a PR from a branch: `fj pr create --repo <owner>/<repo> --head <branch> --base main --autofill`
    - Check auth outside a repo: `fj -H ${forgejoHost} whoami`
    - Check auth inside a repo with a Forgejo remote: `fj whoami`
  '';

  zshrc = pkgs.writeText "t3code-zshrc" ''
    export PATH=/run/current-system/sw/bin:$PATH
    export COLORTERM=truecolor
    export CODEX_HOME=${lib.escapeShellArg codexHome}
    export DOCKER_HOST=${lib.escapeShellArg "unix:///run/user/${toString uid}/podman/podman.sock"}
    export FJ_FALLBACK_HOST=${lib.escapeShellArg forgejoUrl}
    export T3CODE_HOME=${lib.escapeShellArg state}
    export XDG_RUNTIME_DIR=${lib.escapeShellArg "/run/user/${toString uid}"}

    if [ -d ${lib.escapeShellArg repos} ]; then
      cd ${lib.escapeShellArg repos}
    fi

    eval "$(${lib.getExe pkgs.direnv} hook zsh)"
    eval "$(${lib.getExe pkgs.starship} init zsh)"
  '';

  zshenv = pkgs.writeText "t3code-zshenv" ''
    if [ -z "''${T3CODE_DIRENV_ZSHENV:-}" ] && command -v direnv >/dev/null 2>&1; then
      export T3CODE_DIRENV_ZSHENV=1
      export DIRENV_LOG_FORMAT="''${DIRENV_LOG_FORMAT-}"
      eval "$(direnv export zsh 2>/dev/null || true)"
      unset T3CODE_DIRENV_ZSHENV
    fi
  '';

  direnvrc = pkgs.writeText "t3code-direnvrc" ''
    source ${pkgs.nix-direnv}/share/nix-direnv/direnvrc
    dotenv_if_exists .env
    dotenv_if_exists .env.local
    dotenv_if_exists .secrets
  '';
  direnvConfig = pkgs.writeText "t3code-direnv.toml" ''
    [whitelist]
    prefix = [${builtins.toJSON repos}]
  '';

  prepare = pkgs.writeShellApplication {
    name = "t3code-prepare";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      set -euo pipefail

      old_home=/srv/agents/t3code/home
      old_state=/srv/agents/t3code/state
      old_workspace=/srv/agents/t3code/workspace

      install -d -m 0750 ${lib.escapeShellArg home}
      install -d -m 0750 ${lib.escapeShellArg repos}
      install -d -m 0750 ${lib.escapeShellArg state}
      install -d -m 0700 ${lib.escapeShellArg codexHome}
      install -d -m 0750 ${lib.escapeShellArg "${codexHome}/skills"}
      install -d -m 0750 ${lib.escapeShellArg "${home}/.config/direnv"}
      install -d -m 0700 ${lib.escapeShellArg "${home}/.config/forgejo"}
      install -d -m 0700 ${lib.escapeShellArg "${home}/.local/share/forgejo-cli"}

      if [ -d "$old_home/.codex" ] && [ ! -e ${lib.escapeShellArg "${codexHome}/auth.json"} ]; then
        cp -a "$old_home/.codex/." ${lib.escapeShellArg codexHome}
      fi
      if [ -d "$old_home/.config/forgejo" ] && [ ! -e ${lib.escapeShellArg "${home}/.config/forgejo/token"} ]; then
        cp -a "$old_home/.config/forgejo/." ${lib.escapeShellArg "${home}/.config/forgejo"}
      fi
      if [ -e "$old_home/.git-credentials" ] && [ ! -e ${lib.escapeShellArg "${home}/.git-credentials"} ]; then
        cp -a "$old_home/.git-credentials" ${lib.escapeShellArg "${home}/.git-credentials"}
      fi
      if [ -d "$old_state" ] && [ ! -e ${lib.escapeShellArg "${state}/userdata/settings.json"} ]; then
        cp -a "$old_state/." ${lib.escapeShellArg state}
      fi
      if [ -d "$old_workspace" ] && [ ! -e ${lib.escapeShellArg "${repos}/FORGEJO.md"} ]; then
        cp -a "$old_workspace/." ${lib.escapeShellArg repos}
      fi

      link_store_path() {
        dest="$1"
        source="$2"
        if [ -e "$dest" ] && [ ! -L "$dest" ]; then
          rm -rf "$dest"
        fi
        ln -sfn "$source" "$dest"
      }

      link_store_path ${lib.escapeShellArg "${codexHome}/AGENTS.md"} ${lib.escapeShellArg (toString agentAssets.codexFiles.agents)}
      link_store_path ${lib.escapeShellArg "${codexHome}/config.toml"} ${lib.escapeShellArg (toString codexConfig)}
      link_store_path ${lib.escapeShellArg "${codexHome}/hooks.json"} ${lib.escapeShellArg (toString agentAssets.codexFiles.hooks)}
      ${codexSkillLinks}

      settings_path=${lib.escapeShellArg "${state}/userdata/settings.json"}
      if [ ! -e "$settings_path" ]; then
        install -d -m 0750 "$(dirname "$settings_path")"
        install -m 0600 ${serverSettings} "$settings_path"
      fi
      settings_tmp="$(mktemp)"
      jq \
        --arg codex_binary ${lib.escapeShellArg (lib.getExe codexWithDirenv)} \
        --arg codex_home ${lib.escapeShellArg codexHome} \
        '
          .providers.codex.binaryPath = $codex_binary
          | .providers.codex.homePath = $codex_home
          | .providers.claudeAgent.enabled = false
          | .providers.cursor.enabled = false
          | .providers.opencode.enabled = false
          | .providers.pi.enabled = false
          | .textGenerationModelSelection.instanceId = "codex"
          | .textGenerationModelSelection.model = "gpt-5.5"
        ' \
        "$settings_path" > "$settings_tmp"
      install -m 0600 "$settings_tmp" "$settings_path"
      rm -f "$settings_tmp"

      install -m 0600 ${gitConfig} ${lib.escapeShellArg "${home}/.gitconfig"}
      install -m 0644 ${direnvConfig} ${lib.escapeShellArg "${home}/.config/direnv/direnv.toml"}
      install -m 0644 ${direnvrc} ${lib.escapeShellArg "${home}/.config/direnv/direnvrc"}
      install -m 0644 ${zshenv} ${lib.escapeShellArg "${home}/.zshenv"}
      install -m 0644 ${zshrc} ${lib.escapeShellArg "${home}/.zshrc"}
      install -m 0644 ${forgejoGuide} ${lib.escapeShellArg "${repos}/FORGEJO.md"}

      token_path=${lib.escapeShellArg "${home}/.config/forgejo/token"}
      fj_keys_path=${lib.escapeShellArg "${home}/.local/share/forgejo-cli/keys.json"}
      git_credentials=${lib.escapeShellArg "${home}/.git-credentials"}
      if [ -r "$token_path" ]; then
        token="$(tr -d '\r\n' < "$token_path")"
        if [ -n "$token" ]; then
          keys_tmp="$(mktemp)"
          jq -n \
            --arg host ${lib.escapeShellArg forgejoHost} \
            --arg name ${lib.escapeShellArg forgejoUser} \
            --arg token "$token" \
            '{hosts: {($host): {type: "Application", name: $name, token: $token}}, aliases: {}, default_ssh: []}' \
            > "$keys_tmp"
          install -m 0600 "$keys_tmp" "$fj_keys_path"
          rm -f "$keys_tmp"

          credentials_tmp="$(mktemp)"
          encoded_user="$(jq -rn --arg value ${lib.escapeShellArg forgejoUser} '$value | @uri')"
          encoded_token="$(jq -rn --arg value "$token" '$value | @uri')"
          printf 'https://%s:%s@%s\n' "$encoded_user" "$encoded_token" ${lib.escapeShellArg forgejoHost} > "$credentials_tmp"
          install -m 0600 "$credentials_tmp" "$git_credentials"
          rm -f "$credentials_tmp"
        fi
      fi
    '';
  };
in
{
  users.groups.t3code = { };
  users.users.t3code = {
    inherit uid;
    description = "T3 Code service";
    isSystemUser = true;
    group = "t3code";
    inherit home;
    createHome = true;
    autoSubUidGidRange = true;
    linger = true;
    shell = pkgs.zsh;
  };

  environment.systemPackages = [
    pkgs.direnv
    codexWithDirenv
    pkgs.nix-direnv
    package
    pkgs.podman-compose
    prepare
    pkgs.starship
    pkgs.zsh
  ];

  systemd.tmpfiles.rules = [
    "d ${home} 0750 t3code t3code -"
    "d ${codexHome} 0700 t3code t3code -"
    "d ${codexHome}/skills 0750 t3code t3code -"
    "d ${state} 0750 t3code t3code -"
    "d ${repos} 0750 t3code t3code -"
  ];

  systemd.services.t3code = {
    description = "T3 Code headless service";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "network-online.target"
      "user@${toString uid}.service"
    ];
    after = [
      "network-online.target"
      "user@${toString uid}.service"
    ];
    path = [
      package
      codexWithDirenv
      llmPkgs.codex
      pkgs.bashInteractive
      pkgs.coreutils
      pkgs.direnv
      pkgs.fd
      pkgs.forgejo-cli
      pkgs.git
      pkgs.jq
      pkgs.nodejs
      pkgs.nix-direnv
      pkgs.nix
      pkgs.podman
      pkgs.python3
      pkgs.ripgrep
      pkgs.starship
      pkgs.uv
      pkgs.zsh
    ];
    environment = {
      HOME = home;
      USER = "t3code";
      LOGNAME = "t3code";
      CODEX_HOME = codexHome;
      DOCKER_HOST = "unix:///run/user/${toString uid}/podman/podman.sock";
      T3CODE_HOME = state;
      T3CODE_HOST = "127.0.0.1";
      T3CODE_PORT = toString port;
      T3CODE_TELEMETRY_ENABLED = "false";
      XDG_RUNTIME_DIR = "/run/user/${toString uid}";
    };
    serviceConfig = {
      User = "t3code";
      Group = "t3code";
      WorkingDirectory = repos;
      ExecStartPre = "${lib.getExe prepare}";
      ExecStart = "${lib.getExe package} serve --base-dir ${state} --host 127.0.0.1 --port ${toString port} ${repos}";
      Restart = "always";
      RestartSec = 10;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ReadWritePaths = [
        "/run/user/${toString uid}"
        home
      ];
      TasksMax = 4096;
      TimeoutStartSec = 900;
    };
  };

  services.tailscaleServe.services.t3code = {
    target = "http://127.0.0.1:${toString port}";
    wants = [ "t3code.service" ];
    after = [ "t3code.service" ];
  };
}
