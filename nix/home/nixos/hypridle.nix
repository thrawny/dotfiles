{ dotfiles, pkgs, ... }:
let
  keepawake = pkgs.callPackage ../../packages/keepawake.nix { };
in
{
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "${dotfiles}/bin/hypr-display-recover --after-sleep";
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
          condition_cmd = "${keepawake}/bin/keepawake can-screen-sleep";
          condition_retry = 10;
        }
        {
          timeout = 1800;
          on-timeout = "systemctl suspend";
          condition_cmd = "${keepawake}/bin/keepawake can-suspend";
          condition_retry = 10;
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
      # Closed-lid sessions obey the battery floor; other sessions preserve this safety net.
      ExecCondition = "${keepawake}/bin/keepawake can-lid-suspend";
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
