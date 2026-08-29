# nirius provides scratchpads, window focus, and workspace focus history.
# App jumping is bound as an xremap chord (Alt-a prefix) in ../xremap.nix.
{ config, pkgs, ... }:
{
  home.packages = [ pkgs.nirius ];

  programs.niri.settings.spawn-at-startup = [
    {
      command = [
        "niriusd"
        "--workspace-directory"
        "dotfiles=${config.home.homeDirectory}/dotfiles"
      ];
    }
  ];
}
