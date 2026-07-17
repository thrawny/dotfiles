# Agent session overlay (agent-switch, Rust GTK4 app) + nirius (app-jump focus daemon)
# Assumes agent-switch is available on PATH (e.g., ~/.cargo/bin)
# App jumping is bound as an xremap chord (Alt-a prefix) in ../xremap.nix
{ pkgs, ... }:
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
      { command = [ "niriusd" ]; }
    ];
  };
}
