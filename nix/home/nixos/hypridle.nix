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
        # Safety net: if the laptop is closed and unplugged, suspend even when
        # an idle inhibitor (e.g. caffeine/video call) was accidentally left on.
        {
          timeout = 60;
          ignore_inhibit = true;
          on-timeout = "${dotfiles}/bin/suspend-if-lid-closed-on-battery";
        }
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
}
