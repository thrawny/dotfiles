{
  codexSharedSkillNames,
  claudeSharedSkillNames,
  config,
  configSource,
  dotfiles,
  lib,
  noLinuxOnly,
  ...
}:
let
  hmLib = lib.hm;
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
  home = {
    sessionPath = [ "${config.home.homeDirectory}/dotfiles/bin" ];

    activation = {
      seedCodexConfig = seedExample "config/codex/config.example.toml" "config/codex/config.toml";
      seedClaudeSettings = seedExample "config/claude/settings.example.json" "config/claude/settings.json";
      seedPiSettings = seedExample "config/pi/settings.example.json" "config/pi/settings.json";

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
      ".codex/config.toml".source = configSource "codex/config.toml";
      ".pi/agent/settings.json".source = configSource "pi/settings.json";
      ".claude/settings.json".source = configSource "claude/settings.json";
    };
  };
}
