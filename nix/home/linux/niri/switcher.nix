# Agent switcher (Rust GTK4 app)
# Adds agent-switch package and startup daemon
{ pkgs, self, ... }:
let
  inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) agent-switch;
in
{
  home.packages = [ agent-switch ];

  programs.niri.settings = {
    spawn-at-startup = [
      {
        command = [
          "${agent-switch}/bin/agent-switch"
          "niri"
        ];
      }
    ];

    binds = {
      "Mod+S" = {
        action.spawn = [
          "${agent-switch}/bin/agent-switch"
          "niri"
          "--toggle"
        ];
        hotkey-overlay.title = "Agent Switcher";
      };
    };
  };
}
