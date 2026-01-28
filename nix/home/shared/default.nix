{
  config,
  lib,
  pkgs,
  dotfiles,
  username,
  ...
}@args:
{
  imports = [
    # Shared cross-platform modules
    ./home-base.nix
    ./packages.nix
    ./btop.nix
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
    ./mise.nix
  ];

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

  # Fuzzy search for Nix packages
  programs.nix-search-tv = {
    enable = true;
    settings = {
      indexes = [
        "nixpkgs"
        "home-manager"
        "nur"
        "nixos"
      ];
      update_interval = "168h";
    };
  };

  # Full nix-search-tv script with nix-shell, homepage, source navigation
  home.packages = [
    (pkgs.writeShellScriptBin "ns" (builtins.readFile "${pkgs.nix-search-tv.src}/nixpkgs.sh"))
  ];
}
