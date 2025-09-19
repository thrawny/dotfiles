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
    ./direnv.nix
    ./git.nix
    ./ghostty.nix
    ./hyprland/default.nix
    ./hypridle.nix
    ./hyprlock.nix
    ./hyprpaper.nix
    ./k9s.nix
    ./mako.nix
    ./nvim.nix
    ./npm.nix
    ./starship.nix
    ./tmux.nix
    ./walker.nix
    ./waybar.nix
    ./zsh.nix
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "24.05";

  home.packages = with pkgs; [
    nodejs_24
    python313
    starship
    uv
    gh
  ];

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

  # Cursor configuration - for Linux it goes in ~/.config/Cursor/User/
  home.file.".config/Cursor/User/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/cursor/settings.json";
  home.file.".config/Cursor/User/keybindings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/cursor/keybindings.linux.json";

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
