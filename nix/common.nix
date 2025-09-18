{ lib, pkgs, ... }:

let
  username = "jonas";
  dotfiles = "/home/${username}/dotfiles";
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
    kitty
    fuzzel
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = {
    inherit dotfiles username;
  };

  home-manager.users.${username} = import ./modules/home-manager/default.nix;
}
