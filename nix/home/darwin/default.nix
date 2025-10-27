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
    ./lazygit.nix
    ./aerospace.nix
    ./setup.nix
  ];

  home = {
    inherit username;
    homeDirectory = "/Users/${username}";
  };
}
