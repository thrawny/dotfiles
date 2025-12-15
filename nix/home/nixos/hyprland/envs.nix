_: {
  wayland.windowManager.hyprland.settings = {
    env = [
      # Cursor theme/size so GTK, XWayland, and Hypr match.
      "XCURSOR_SIZE,24"
      "HYPRCURSOR_SIZE,24"
      "XCURSOR_THEME,Adwaita"
      "HYPRCURSOR_THEME,Adwaita"

      # Wayland-first hints for common toolkits (with fallbacks).
      "GDK_BACKEND,wayland,x11,*"
      "QT_QPA_PLATFORM,wayland;xcb"
      "QT_STYLE_OVERRIDE,kvantum"
      "SDL_VIDEODRIVER,wayland"
      "MOZ_ENABLE_WAYLAND,1"
      "ELECTRON_OZONE_PLATFORM_HINT,wayland"
      "OZONE_PLATFORM,wayland"

      # Session desktop identifier (XDG_CURRENT_DESKTOP and XDG_SESSION_TYPE set by NixOS).
      "XDG_SESSION_DESKTOP,Hyprland"

      # Set a sane default editor for spawned shells.
      "EDITOR,nvim"
    ];

    xwayland.force_zero_scaling = true;

    ecosystem.no_update_news = true;
  };
}
