{ dotfiles, ... }:
{
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "${dotfiles}/bin/dpms-on";
      };
      listener = [
        {
          timeout = 300;
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 330;
          on-timeout = "${dotfiles}/bin/dpms-off";
          on-resume = "${dotfiles}/bin/dpms-on";
        }
        {
          timeout = 1800;
          on-timeout = "systemctl suspend";
        }
      ];
    };
  };

  # This is deliberately a recurring timer rather than a hypridle listener:
  # the final dock/display may be unplugged after the system is already idle.
  systemd.user.services.closed-lid-suspend-safety = {
    Unit.Description = "Suspend a closed, undocked laptop";
    Service = {
      Type = "oneshot";
      ExecStart = "${dotfiles}/bin/suspend-if-lid-closed-on-battery";
    };
  };

  systemd.user.timers.closed-lid-suspend-safety = {
    Unit.Description = "Periodically check whether a closed laptop was undocked";
    Timer = {
      OnStartupSec = "5m";
      OnUnitActiveSec = "5m";
      Unit = "closed-lid-suspend-safety.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
