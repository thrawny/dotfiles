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
      ];
    };
  };
}
