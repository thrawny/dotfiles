{
  config,
  lib,
  pkgs,
  ...
}:
let
  keepawake = pkgs.callPackage ../../packages/keepawake.nix {
    defaultConfig =
      if config.dotfiles.keepawake.deviceType == "desktop" then
        ../../../config/keepawake/desktop.example.toml
      else
        ../../../config/keepawake/config.example.toml;
  };
in
{
  options.dotfiles.keepawake.deviceType = lib.mkOption {
    type = lib.types.enum [
      "laptop"
      "desktop"
    ];
    default = "laptop";
    description = "Default keep-awake configuration for newly initialized users.";
  };

  config = {
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
  };
}
