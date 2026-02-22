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
  codexSharedSkillNames = lib.filter (name: name != "skill-creator") sharedSkillNames;
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

        # Codex has built-in skill-creator; don't override it with our shared one.
        codex_base="$HOME/.codex/skills"
        ensure_base_dir "$codex_base"
        for skill in ${lib.concatStringsSep " " (map lib.escapeShellArg codexSharedSkillNames)}; do
          link_skill "$codex_base" "$skill"
        done
        codex_skill_creator="$codex_base/skill-creator"
        if [ -L "$codex_skill_creator" ] && [ "$(readlink "$codex_skill_creator")" = "$skills_src/skill-creator" ]; then
          rm -f "$codex_skill_creator"
        fi

        for base in "$HOME/.claude/skills" "$HOME/.pi/agent/skills"; do
          ensure_base_dir "$base"
          for skill in ${lib.concatStringsSep " " (map lib.escapeShellArg sharedSkillNames)}; do
            link_skill "$base" "$skill"
          done
        done
      '';
    };

    file = {
      # Codex configuration (individual symlinks - Codex 0.88.0+ preserves symlinks)
      ".codex/config.toml".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex/config.toml";
      ".codex/prompts".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex/prompts";
      ".codex/AGENTS.md".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex/AGENTS.md";
      ".codex/rules/code-quality.rules".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex/rules/code-quality.rules";
      ".codex/rules/git.rules".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex/rules/git.rules";
      ".codex/rules/tools.rules".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex/rules/tools.rules";

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
