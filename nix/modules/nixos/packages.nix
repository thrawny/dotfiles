{
  pkgs,
  lib,
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
    walker
    waybar
    wl-clipboard
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
    vim
    wget
    unzip
    chromium
    spotify
    btop
    powertop
    fastfetch
    docker-compose
    code-cursor-fhs
  ];

  selectedSystemPackages = lib.lists.subtractLists excludePackages systemPackages;
  allSystemPackages = hyprlandPackages ++ selectedSystemPackages;
in
{
  systemPackages = allSystemPackages;
  homePackages = with pkgs; [ ];
}
