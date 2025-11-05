{ pkgs, ... }:
{
  # Configure keyd-application-mapper to handle per-app key remapping
  # This allows Ghostty to receive super+c/v directly without keyd remapping them

  # Create the app.conf file for keyd-application-mapper
  xdg.configFile."keyd/app.conf".text = ''
    [zen-beta]
    meta.a = C-a
    meta.c = C-c
    meta.v = C-v
    meta.x = C-x
  '';

  # Enable keyd-application-mapper systemd user service
  systemd.user.services.keyd-application-mapper = {
    Unit = {
      Description = "keyd application-specific key remapping";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.keyd}/bin/keyd-application-mapper";
      Restart = "on-failure";
      RestartSec = 3;
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
