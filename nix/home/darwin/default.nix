{
  config,
  pkgs,
  username,
  ...
}:
{
  imports = [
    # Import all shared cross-platform modules
    ../shared

    # Darwin-specific modules
    ./ghostty.nix
    ./aerospace.nix
    ./setup.nix
    ./t3code.nix
    ./openclaw-node.nix
    ./nightly-app-update.nix
  ];

  # Determinate owns the Nix installation, daemon, and configuration on macOS.
  # Do not let Home Manager generate nix.conf or add upstream Nix to PATH.
  nix = {
    enable = false;
    package = null;
  };

  # Force XDG paths on macOS (apps default to ~/Library/Application Support/ otherwise)
  xdg.enable = true;

  # Keep zsh dotfiles in ~ (not ~/.config/zsh) despite xdg.enable
  programs.zsh.dotDir = config.home.homeDirectory;

  home = {
    inherit username;
    homeDirectory = "/Users/${username}";
    packages = [ pkgs.flock ];
  };
}
