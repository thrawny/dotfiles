_:
{
  wayland.windowManager.hyprland.settings = {
    windowrule = [
      # Prevent sudden maximize events when spawning toolkits.
      "suppressevent maximize, class:.*"

      # Keep Chromium-based apps tiled unless explicitly floated.
      "tile, class:^(chromium)$"

      # Float common control panels.
      "float, class:^(org.pulseaudio.pavucontrol|blueberry.py|.blueman-manager-wrapped)$"
      "float, class:^(steam)$"
      "float, class:^(1Password)$"
      "float, class:^(nm-connection-editor)$"
      "fullscreen, class:^(com.libretro.RetroArch)$"

      # Adjust opacity for a touch of depth without hampering focus.
      "opacity 0.97 0.9, class:.*"
      "opacity 1 1, class:^(chromium|google-chrome|google-chrome-unstable)$, title:.*Youtube.*"
      "opacity 1 0.97, class:^(chromium|google-chrome|google-chrome-unstable)$"
      "opacity 0.97 0.9, initialClass:^(chrome-.*-Default)$"
      "opacity 1 1, initialClass:^(chrome-youtube.*-Default)$"
      "opacity 1 1, class:^(zoom|vlc|org.kde.kdenlive|com.obsproject.Studio|steam)$"

      # Smooth XWayland drag behaviour.
      "nofocus,class:^$,title:^$,xwayland:1,floating:1,fullscreen:0,pinned:0"

      # Center the clipse clipboard manager when launched.
      "float, class:(clipse)"
      "size 622 652, class:(clipse)"
      "stayfocused, class:(clipse)"
    ];

    windowrulev2 = [
      "workspace name:p, class:^(Spotify)$"
      "workspace name:b, class:^(zen-beta)$"
    ];

    layerrule = [
      "blur,wofi"
      "blur,waybar"
    ];
  };
}
