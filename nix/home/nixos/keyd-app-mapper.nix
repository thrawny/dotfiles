{ pkgs, ... }:
{
  # Configure keyd-application-mapper to handle per-app key remapping
  # This allows Ghostty to receive super+c/v directly without keyd remapping them

  # Create the app.conf file for keyd-application-mapper
  xdg.configFile."keyd/app.conf".text = ''
    # Global default - Mac-style shortcuts for all apps
    [*]
    meta.a = C-a
    meta.c = C-c
    meta.v = C-v
    meta.x = C-x

    # Ghostty terminal - override to pass through super keys unchanged
    # so Ghostty's internal keybindings can handle them
    [com.mitchellh.ghostty]
    meta.a = M-a
    meta.c = M-c
    meta.v = M-v
    meta.x = M-x
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
