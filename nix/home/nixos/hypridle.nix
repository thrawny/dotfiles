{ dotfiles, ... }:
let
  # Detect compositor and run appropriate command
  dpmsOff = ''
    if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
      hyprctl dispatch dpms off
    elif [ -n "$NIRI_SOCKET" ]; then
      niri msg action power-off-monitors
    fi
  '';
  dpmsOn = ''
    if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
      ${dotfiles}/bin/wake-monitors-poll on-resume
    elif [ -n "$NIRI_SOCKET" ]; then
      niri msg action power-on-monitors
    fi
  '';
in
{
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = ''
          if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
            ${dotfiles}/bin/wake-monitors-poll after-sleep
          elif [ -n "$NIRI_SOCKET" ]; then
            niri msg action power-on-monitors
          fi
        '';
      };
      listener = [
        {
          timeout = 300;
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 330;
          on-timeout = dpmsOff;
          on-resume = dpmsOn;
        }
      ];
    };
  };
}
