# nirius (scratchpads, window focus, workspace focus history) and the
# headless agent-switch daemon (hooks -> socket -> sessions.json; waybar
# reads it via `agent-switch list`). Both assumed on PATH (~/.cargo/bin).
# App jumping is bound as an xremap chord (Alt-a prefix) in ../xremap.nix.
{ config, pkgs, ... }:
{
  home.packages = [ pkgs.nirius ];

  programs.niri.settings = {
    spawn-at-startup = [
      {
        command = [
          "agent-switch"
          "serve"
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
