{ lib, ... }:
{
  wayland.windowManager.hyprland.settings = {
    env = [
      # Scale-aware GTK apps; tweak if the monitor scale changes.
      "GDK_SCALE,1"

      # Cursor theme/size so GTK, XWayland, and Hypr match.
      "XCURSOR_SIZE,24"
      "HYPRCURSOR_SIZE,24"
      "XCURSOR_THEME,Adwaita"
      "HYPRCURSOR_THEME,Adwaita"

      # Wayland-first hints for common toolkits.
      "GDK_BACKEND,wayland"
      "QT_QPA_PLATFORM,wayland"
      "QT_STYLE_OVERRIDE,kvantum"
      "SDL_VIDEODRIVER,wayland"
      "MOZ_ENABLE_WAYLAND,1"
      "ELECTRON_OZONE_PLATFORM_HINT,wayland"
      "OZONE_PLATFORM,wayland"

      # Chromium flags ensure Wayland + XCompose support by default.
      "CHROMIUM_FLAGS,\"--enable-features=UseOzonePlatform --ozone-platform=wayland --gtk-version=4\""

      # Make desktop entries discoverable for launchers such as Fuzzel/Wofi.
      "XDG_DATA_DIRS,$XDG_DATA_DIRS:$HOME/.nix-profile/share:/nix/var/nix/profiles/default/share"

      # Set a sane default editor for spawned shells.
      "EDITOR,nvim"
    ];

    xwayland.force_zero_scaling = true;
  };
}
