{
  config,
  lib,
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
      seedCursorSettings = seedExample "config/cursor/settings.example.json" "config/cursor/settings.json";
      seedPiSettings = seedExample "config/pi/settings.example.json" "config/pi/settings.json";
      seedClaudeJson = hmLib.dag.entryBefore [ "linkGeneration" ] ''
        claude_json="${config.home.homeDirectory}/.claude.json"
        if [ ! -s "$claude_json" ]; then
          printf '%s\n' '{"numStartups":1,"installMethod":"native","autoUpdates":false,"theme":"dark-daltonized","editorMode":"vim","hasCompletedOnboarding":true}' > "$claude_json"
        fi
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
      ".pi/agent/prompts".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/prompts";
      ".pi/agent/skills".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/skills";
      ".pi/agent/extensions".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/extensions";
      ".pi/agent/themes".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/pi/themes";

      # Claude configuration
      ".claude/commands".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/commands";
      ".claude/settings.json".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/settings.json";
      ".claude/agents".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/agents";
      ".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/skills";
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
