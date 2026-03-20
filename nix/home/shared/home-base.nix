{
  config,
  lib,
  pkgs,
  ...
}@args:
let
  hmLib = lib.hm;
  containerAssets = args.containerAssets or null;
  dotfiles = args.dotfiles or null;
  repoBacked = containerAssets == null;
  gitIdentity = {
    name = null;
    email = null;
  }
  // (args.gitIdentity or { });
  configPath =
    rel: if repoBacked then "${dotfiles}/config/${rel}" else containerAssets.config + "/${rel}";
  skillPath =
    name: if repoBacked then "${dotfiles}/skills/${name}" else containerAssets.skills + "/${name}";
  skillsRoot = if repoBacked then ../../../skills else containerAssets.skills;
  sharedSkillNames = builtins.attrNames (
    lib.filterAttrs (name: type: type == "directory" && !(lib.hasPrefix "." name)) (
      builtins.readDir skillsRoot
    )
  );
  linuxOnlySkills = [
    "wayvoice"
    "skill-eval"
  ];
  noLinuxOnly = lib.filter (name: !builtins.elem name linuxOnlySkills) sharedSkillNames;
  codexSharedSkillNames = lib.filter (
    name: !builtins.elem name (linuxOnlySkills ++ [ "skill-creator" ])
  ) sharedSkillNames;
  claudeSharedSkillNames = lib.filter (
    name: !builtins.elem name (linuxOnlySkills ++ [ "skill-creator" ])
  ) sharedSkillNames;
  seedExample =
    example: destination:
    if repoBacked then
      hmLib.dag.entryBefore [ "linkGeneration" ] ''
        repo=${lib.escapeShellArg dotfiles}
        example_path="$repo/${example}"
        dest_path="$repo/${destination}"
        if [ ! -s "$dest_path" ] && [ -e "$example_path" ]; then
          install -Dm0644 "$example_path" "$dest_path"
        fi
      ''
    else
      hmLib.dag.entryBefore [ "linkGeneration" ] ''
        dest_path=${lib.escapeShellArg destination}
        if [ ! -s "$dest_path" ]; then
          install -Dm0644 ${lib.escapeShellArg (toString example)} "$dest_path"
        fi
      '';
  configSource =
    rel: if repoBacked then config.lib.file.mkOutOfStoreSymlink (configPath rel) else configPath rel;
  skillFiles =
    base: names:
    lib.listToAttrs (
      map (
        name:
        lib.nameValuePair "${base}/${name}" {
          source =
            if repoBacked then config.lib.file.mkOutOfStoreSymlink (skillPath name) else skillPath name;
        }
      ) names
    );
in
{
  nix = {
    package = lib.mkDefault pkgs.nix;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      extra-substituters = [
        "https://cache.numtide.com"
        "https://claude-code.cachix.org"
      ];
      extra-trusted-public-keys = [
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      ];
    };
  };

  home = {
    stateVersion = "24.05";

    sessionVariables = {
      PYTHONDONTWRITEBYTECODE = "1";
      PYTHONUNBUFFERED = "1";
      GOPATH = "$HOME/go";
      PNPM_HOME = "$HOME/.local/share/pnpm";
      EDITOR = "nvim";
      VISUAL = "nvim";
      MANPAGER = "nvim +Man!";
      AWS_PAGER = "";
      LANG = "en_US.UTF-8";
      LC_ALL = "en_US.UTF-8";
      LC_CTYPE = "en_US.UTF-8";
      KUBECTL_EXTERNAL_DIFF = "kubectl-dyff";
    };

    sessionPath = [
      "${config.home.homeDirectory}/.cargo/bin"
      "${config.home.homeDirectory}/.npm-global/bin"
      "${config.home.homeDirectory}/.local/share/pnpm"
      "${config.home.homeDirectory}/.local/bin"
      "${config.home.homeDirectory}/go/bin"
    ]
    ++ lib.optionals repoBacked [ "${config.home.homeDirectory}/dotfiles/bin" ];

    activation = {
      seedCodexConfig =
        if repoBacked then
          seedExample "config/codex/config.example.toml" "config/codex/config.toml"
        else
          seedExample (configPath "codex/config.example.toml") "${config.home.homeDirectory}/.codex/config.toml";
      seedClaudeSettings =
        if repoBacked then
          seedExample "config/claude/settings.example.json" "config/claude/settings.json"
        else
          hmLib.dag.entryBefore [ "linkGeneration" ] ''
            dest_path=${lib.escapeShellArg "${config.home.homeDirectory}/.claude/settings.json"}
            if [ ! -s "$dest_path" ]; then
              install -d -m0755 "$(dirname "$dest_path")"
              ${pkgs.jq}/bin/jq '
                del(.hooks, .enabledPlugins)
                | .statusLine.command = "python3 ~/.claude/status_line.py"
              ' ${lib.escapeShellArg (toString (configPath "claude/settings.example.json"))} > "$dest_path"
              chmod 0644 "$dest_path"
            fi
          '';
      seedPiSettings =
        if repoBacked then
          seedExample "config/pi/settings.example.json" "config/pi/settings.json"
        else
          seedExample (configPath "pi/settings.example.json") "${config.home.homeDirectory}/.pi/agent/settings.json";
      seedClaudeJson = hmLib.dag.entryBefore [ "linkGeneration" ] ''
        claude_json="${config.home.homeDirectory}/.claude.json"
        if [ ! -s "$claude_json" ]; then
          printf '%s\n' '{"numStartups":1,"installMethod":"native","autoUpdates":false,"theme":"dark-daltonized","editorMode":"vim","hasCompletedOnboarding":true}' > "$claude_json"
        fi
      '';
    }
    // lib.optionalAttrs repoBacked {
      linkSharedSkills = hmLib.dag.entryAfter [ "linkGeneration" ] ''
        repo=${lib.escapeShellArg dotfiles}
        skills_src="$repo/skills"

        ensure_base_dir() {
          base="$1"
          if [ -L "$base" ]; then
            echo "Replacing legacy skills symlink at $base"
            rm -f "$base"
          elif [ -e "$base" ] && [ ! -d "$base" ]; then
            echo "Replacing non-directory skills path at $base"
            rm -rf "$base"
          fi
          mkdir -p "$base"
        }

        link_skill() {
          base="$1"
          skill="$2"
          src="$skills_src/$skill"
          dst="$base/$skill"
          if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
            return
          fi
          rm -rf "$dst"
          ln -s "$src" "$dst"
        }

        prune_removed_repo_skills() {
          base="$1"
          for dst in "$base"/*; do
            [ -L "$dst" ] || continue
            src="$(readlink "$dst")"
            case "$src" in
              "$skills_src"/*)
                if [ ! -e "$src" ]; then
                  echo "Removing stale shared skill link at $dst"
                  rm -f "$dst"
                fi
                ;;
            esac
          done
        }

        codex_base="$HOME/.codex/skills"
        ensure_base_dir "$codex_base"
        prune_removed_repo_skills "$codex_base"
        for skill in ${lib.concatStringsSep " " (map lib.escapeShellArg codexSharedSkillNames)}; do
          link_skill "$codex_base" "$skill"
        done
        codex_skill_creator="$codex_base/skill-creator"
        if [ -L "$codex_skill_creator" ] && [ "$(readlink "$codex_skill_creator")" = "$skills_src/skill-creator" ]; then
          rm -f "$codex_skill_creator"
        fi

        claude_base="$HOME/.claude/skills"
        ensure_base_dir "$claude_base"
        prune_removed_repo_skills "$claude_base"
        for skill in ${lib.concatStringsSep " " (map lib.escapeShellArg claudeSharedSkillNames)}; do
          link_skill "$claude_base" "$skill"
        done
        claude_skill_creator="$claude_base/skill-creator"
        if [ -L "$claude_skill_creator" ] && [ "$(readlink "$claude_skill_creator")" = "$skills_src/skill-creator" ]; then
          rm -f "$claude_skill_creator"
        fi

        pi_base="$HOME/.pi/agent/skills"
        ensure_base_dir "$pi_base"
        prune_removed_repo_skills "$pi_base"
        for skill in ${lib.concatStringsSep " " (map lib.escapeShellArg noLinuxOnly)}; do
          link_skill "$pi_base" "$skill"
        done
      '';
    };

    file = {
      ".codex/hooks.json".source = configSource "codex/hooks.json";
      ".codex/prompts".source = configSource "codex/prompts";
      ".codex/AGENTS.md".source = configSource "codex/AGENTS.md";

      ".pi/agent/models.json".source = configSource "pi/models.json";
      ".pi/agent/AGENTS.md".source = configSource "pi/AGENTS.md";
      ".pi/agent/prompts".source = configSource "pi/prompts";
      ".pi/agent/extensions".source = configSource "pi/extensions";
      ".pi/agent/themes".source = configSource "pi/themes";

      ".claude/commands".source = configSource "claude/commands";
      ".claude/agents".source = configSource "claude/agents";
      ".claude/rules".source = configSource "claude/rules";
      ".claude/CLAUDE.md".source = configSource "claude/CLAUDE-GLOBAL.md";
      ".claude/.keep".text = "";

      ".gitconfig.local" = lib.mkIf (gitIdentity.name != null || gitIdentity.email != null) {
        text =
          lib.concatStringsSep "\n" (
            [ "[user]" ]
            ++ lib.optionals (gitIdentity.name != null) [ "\tname = ${gitIdentity.name}" ]
            ++ lib.optionals (gitIdentity.email != null) [ "\temail = ${gitIdentity.email}" ]
          )
          + "\n";
      };
    }
    // lib.optionalAttrs repoBacked {
      ".codex/config.toml".source = configSource "codex/config.toml";
      ".pi/agent/settings.json".source = configSource "pi/settings.json";
      ".claude/settings.json".source = configSource "claude/settings.json";
    }
    // lib.optionalAttrs (!repoBacked) {
      ".claude/status_line.py".source = configSource "claude/status_line.py";
    }
    // lib.optionalAttrs (!repoBacked) (skillFiles ".codex/skills" codexSharedSkillNames)
    // lib.optionalAttrs (!repoBacked) (skillFiles ".claude/skills" claudeSharedSkillNames)
    // lib.optionalAttrs (!repoBacked) (skillFiles ".pi/agent/skills" noLinuxOnly);
  };
}
