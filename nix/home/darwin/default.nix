{
  config,
  lib,
  pkgs,
  dotfiles,
  username,
  ...
}:
{
  imports = [
    # Import all shared cross-platform modules
    ../shared

    # Darwin-specific modules
    ./cursor.nix
    ./ghostty.nix

    ./aerospace.nix
    ./setup.nix
  ];

  # Force XDG paths on macOS (apps default to ~/Library/Application Support/ otherwise)
  xdg.enable = true;

  # Keep zsh dotfiles in ~ (not ~/.config/zsh) despite xdg.enable
  programs.zsh.dotDir = config.home.homeDirectory;

  home = {
    inherit username;
    homeDirectory = "/Users/${username}";
  };
}
