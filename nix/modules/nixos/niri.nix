# Niri compositor (system-level)
# Uses pkgs.niri from nixpkgs (cached on Hydra, no local build)
# Config is managed by home-manager via niri-flake.homeModules.config
{ pkgs, ... }:
{
  programs.niri = {
    enable = true;
    package = pkgs.niri;
  };
}
