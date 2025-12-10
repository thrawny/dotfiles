_: {
  wayland.windowManager.hyprland.settings = {
    windowrule = [
      # Prevent sudden maximize events when spawning toolkits.
      "suppressevent maximize, class:.*"

      # Float common control panels.
      "float, class:^(org.pulseaudio.pavucontrol|blueberry.py|.blueman-manager-wrapped)$"
      "float, class:^(1password)$"
      "float, class:^(nm-connection-editor)$"

      # Adjust opacity for a touch of depth without hampering focus.
      "opacity 0.97 0.9, class:.*"
      "opacity 1 1, class:^(cursor)$"

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

      # Steam client on workspace 10 (right monitor)
      "workspace 10, class:^(steam)$"

      # Games on dedicated workspace (left monitor)
      "workspace name:g, class:^(steam_app_.*)$" # Proton/Steam games
      "workspace name:g, class:^(hl2_linux)$" # Half-Life 2
      "workspace name:g, class:^(gamescope)$" # Gamescope compositor
      "fullscreen, class:^(steam_app_.*)$" # Games start fullscreen
    ];

    layerrule = [
      "blur,wofi"
      "blur,waybar"
      "noanim,walker"
    ];
  };
}
