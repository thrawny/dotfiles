{
  pkgs,
  lib,
  nurPkgs,
  excludePackages ? [ ],
}:
let
  hyprlandPackages = with pkgs; [
    hyprshot
    hyprpicker
    hyprsunset
    brightnessctl
    pamixer
    playerctl
    gnome-themes-extra
    pavucontrol
    waybar
    wl-clipboard
    wtype
    networkmanagerapplet # Provides nm-connection-editor GUI
  ];

  systemPackages = with pkgs; [
    curl
    fd
    git
    gnumake
    libnotify
    neovim
    ripgrep
    tmux
    wget
    unzip
    spotify
    btop
    powertop
    fastfetch
    docker-compose
    code-cursor-fhs
    keyd
    nurPkgs.repos.Ev357.helium # Helium browser
  ];

  selectedSystemPackages = lib.lists.subtractLists excludePackages systemPackages;
  allSystemPackages = hyprlandPackages ++ selectedSystemPackages;
in
{
  systemPackages = allSystemPackages;
  homePackages = with pkgs; [ ];
}
