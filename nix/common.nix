{ lib, pkgs, ... }:

let
  username = "jonas";
  dotfiles = "/home/${username}/dotfiles";
  theme = {
    palette = {
      background = "#11111b";
      backgroundAlpha = "rgba(17, 17, 27, 0.92)";
      surface = "#1e1e2e";
      border = "#313244";
      text = "#cdd6f4";
      textMuted = "#6c7086";
      accent = "#89b4fa";
      warning = "#f38ba8";
      success = "#a6e3a1";
    };
    fonts = {
      terminal = {
        family = "CaskaydiaMono Nerd Font";
        size = 13;
      };
    };
  };
in
{
  networking.hostName = lib.mkDefault "nixos";
  system.stateVersion = "25.11";

  services.xserver.enable = false;
  programs.hyprland.enable = true;
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "Hyprland";
      user = username;
    };
  };

  users.users.${username} = {
    isNormalUser = true;
    home = "/home/${username}";
    extraGroups = [ "wheel" "video" "audio" "input" ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;
  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    git
    neovim
    tmux
    ripgrep
    wl-clipboard
    waybar
    foot
    fuzzel
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = {
    inherit dotfiles username theme;
  };

  home-manager.users.${username} = import ./modules/home-manager/default.nix;
}
