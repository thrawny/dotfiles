{ pkgs, ... }:
let
  keepawake = pkgs.callPackage ../../packages/keepawake.nix { };
in
{
  home.packages = [ keepawake ];
  systemd.user.services.dotfiles-keepawake = {
    Unit = {
      Description = "Configurable keep-awake sessions and rules";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${keepawake}/bin/keepawake serve";
      Restart = "on-failure";
      RestartSec = 2;
      UMask = "0077";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
