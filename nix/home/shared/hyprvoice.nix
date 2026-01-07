# Hyprvoice - voice-to-text for Wayland
# Updates via `nix flake update hyprvoice-src`
{
  pkgs,
  self,
  ...
}:
let
  inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) hyprvoice;
in
{
  home.packages = [ hyprvoice ];

  systemd.user.services.hyprvoice = {
    Unit = {
      Description = "Voice-to-text for Wayland";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${hyprvoice}/bin/hyprvoice serve";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
