# Agent session overlay (agent-switch, Rust GTK4 app) + nirius
# Assumes agent-switch and the local nirius fork are available on PATH
# (e.g., ~/.cargo/bin). App jumping is bound as an xremap chord (Alt-a prefix)
# in ../xremap.nix; nirius also tracks debounced workspace focus history.
{ config, pkgs, ... }:
{
  home.packages = [ pkgs.nirius ];

  programs.niri.settings = {
    spawn-at-startup = [
      {
        command = [
          "agent-switch"
          "serve"
          "--niri"
        ];
      }
      {
        command = [
          "niriusd"
          "--workspace-directory"
          "dotfiles=${config.home.homeDirectory}/dotfiles"
        ];
      }
    ];
  };
}
