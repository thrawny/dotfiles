{
  config,
  lib,
  pkgs,
  dotfiles,
  ...
}@args:
let
  hmLib = lib.hm;
  gitIdentity = {
    name = null;
    email = null;
  }
  // (args.gitIdentity or { });
  sharedSkillNames = builtins.attrNames (
    lib.filterAttrs (name: type: type == "directory" && !(lib.hasPrefix "." name)) (
      builtins.readDir ../../../skills
    )
  );
  noSkillCreator = lib.filter (name: name != "skill-creator") sharedSkillNames;
  codexSharedSkillNames = noSkillCreator;
  claudeSharedSkillNames = noSkillCreator;
  seedExample =
    example: destination:
    hmLib.dag.entryBefore [ "linkGeneration" ] ''
      repo=${lib.escapeShellArg dotfiles}
      example_path="$repo/${example}"
      dest_path="$repo/${destination}"
      if [ ! -s "$dest_path" ] && [ -e "$example_path" ]; then
        install -Dm0644 "$example_path" "$dest_path"
      fi
    '';
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

    # Session-wide PATH (inherited by window managers, waybar, etc.)
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
      "${config.home.homeDirectory}/dotfiles/bin"
    ];

    activation = {
      seedCodexConfig = seedExample "config/codex/config.example.toml" "config/codex/config.toml";
      seedClaudeSettings = seedExample "config/claude/settings.example.json" "config/claude/settings.json";
      seedPiSettings = seedExample "config/pi/settings.example.json" "config/pi/settings.json";
      seedClaudeJson = hmLib.dag.entryBefore [ "linkGeneration" ] ''
        claude_json="${config.home.homeDirectory}/.claude.json"
        if [ ! -s "$claude_json" ]; then
          printf '%s\n' '{"numStartups":1,"installMethod":"native","autoUpdates":false,"theme":"dark-daltonized","editorMode":"vim","hasCompletedOnboarding":true}' > "$claude_json"
        fi
      '';
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

        # Codex has built-in skill-creator; don't override it with our shared one.
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

        # Claude uses plugin skill-creator; don't override it with our shared one.
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
        for skill in ${lib.concatStringsSep " " (map lib.escapeShellArg sharedSkillNames)}; do
          link_skill "$pi_base" "$skill"
        done
      '';
    };

    file = {
      # Codex configuration (individual symlinks - Codex 0.88.0+ preserves symlinks)
      ".codex/config.toml".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex/config.toml";
      ".codex/hooks.json".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex/hooks.json";
      ".codex/prompts".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex/prompts";
      ".codex/AGENTS.md".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex/AGENTS.md";

      # Pi configuration
      ".pi/agent/settings.json".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/settings.json";
      ".pi/agent/AGENTS.md".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/AGENTS.md";
      ".pi/agent/prompts".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/prompts";
      ".pi/agent/extensions".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/extensions";
      ".pi/agent/themes".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/themes";

      # Claude configuration
      ".claude/commands".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/commands";
      ".claude/settings.json".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/settings.json";
      ".claude/agents".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/agents";
      ".claude/rules".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/rules";
      ".claude/CLAUDE.md".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/CLAUDE-GLOBAL.md";

      # Ensure .claude directory exists
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
    };
  };
}
