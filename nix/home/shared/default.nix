{
  config,
  lib,
  pkgs,
  dotfiles,
  username,
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
  imports = [
    # Shared cross-platform modules
    ./packages.nix
    ./direnv.nix
    ./git.nix
    ./ghostty.nix
    ./k9s.nix
    ./lazygit.nix
    ./npm.nix
    ./nvim.nix
    ./starship.nix
    ./tmux.nix
    ./zsh.nix
  ];

  home.stateVersion = "24.05";

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

  home.activation.seedCodexConfig = seedExample "config/codex/config.example.toml" "config/codex/config.toml";
  home.activation.seedClaudeSettings = seedExample "config/claude/settings.example.json" "config/claude/settings.json";
  home.activation.seedCursorSettings = seedExample "config/cursor/settings.example.json" "config/cursor/settings.json";

  # Codex configuration
  home.file.".codex".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex";

  # Claude configuration
  home.file.".claude/commands".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/commands";
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/settings.json";
  home.file.".claude/agents".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/agents";
  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/CLAUDE-GLOBAL.md";

  # Ensure .claude directory exists
  home.file.".claude/.keep".text = "";

  home.file.".gitconfig.local" = lib.mkIf (gitIdentity.name != null || gitIdentity.email != null) {
    text =
      lib.concatStringsSep "\n" (
        [ "[user]" ]
        ++ lib.optionals (gitIdentity.name != null) [ "\tname = ${gitIdentity.name}" ]
        ++ lib.optionals (gitIdentity.email != null) [ "\temail = ${gitIdentity.email}" ]
      )
      + "\n";
  };
}
