{
  pkgs,
  nix-index-database,
  ...
}:
{
  imports = [
    # Shared cross-platform modules
    ./home-base.nix
    ./ai-tools.nix
    ./packages/core.nix
    ./packages/workstation.nix
    ./packages/cloud.nix
    ./packages/ai.nix
    ./btop.nix
    ./diffnav.nix
    ./direnv.nix
    ./git.nix
    ./ghostty.nix
    ./k9s.nix
    ./lazygit.nix
    ./npm.nix
    ./nvim.nix
    ./starship.nix
    ./tmux.nix
    ./zmx.nix
    ./zsh.nix

    # Prebuilt nix-index database + comma wrapper
    nix-index-database.homeModules.nix-index
  ];

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
  programs.nix-index-database.comma.enable = true;

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
