# Standalone Home Manager configuration for MacBook Air running Asahi Linux (Fedora).
# Uses Niri compositor with DankMaterialShell.
#
# Required: Install DankMaterialShell
#   curl -fsSL https://install.danklinux.com | sh
#
# DMS provides: panel, spotlight launcher, lock screen, notifications, wallpaper
{
  username,
  ...
}:
{
  imports = [
    ../../home/asahi
  ];

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    stateVersion = "24.05";
  };

  # Note: Display output and debug settings are now in config/niri/config.kdl
}
