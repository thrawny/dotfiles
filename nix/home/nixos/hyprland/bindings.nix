{
  lib,
  pkgs,
  username,
  dotfiles,
  ...
}:
let
  mod = "$mod";
  home = "/home/${username}";

  wallpapers = [
    "${dotfiles}/assets/tokyo.jpg"
    "${dotfiles}/assets/nasa.jpg"
  ];

  cycleWallpaper = pkgs.writeShellScript "cycle-wallpaper" ''
    STATE_FILE="/tmp/wallpaper-index"
    WALLPAPERS=(${builtins.concatStringsSep " " (map (w: ''"${w}"'') wallpapers)})
    COUNT=''${#WALLPAPERS[@]}

    INDEX=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
    INDEX=$(( (INDEX + 1) % COUNT ))
    echo "$INDEX" > "$STATE_FILE"

    WALLPAPER="''${WALLPAPERS[$INDEX]}"
    hyprctl hyprpaper wallpaper ",$WALLPAPER"
  '';

  workspaceDigits = lib.range 1 9;

  workspaceBinds =
    (map (n: "${mod}, ${builtins.toString n}, workspace, ${builtins.toString n}") workspaceDigits)
    ++ [ "${mod}, 0, workspace, 10" ];

  moveWorkspaceBinds =
    (map (
      n: "${mod} SHIFT, ${builtins.toString n}, movetoworkspace, ${builtins.toString n}"
    ) workspaceDigits)
    ++ [ "${mod} SHIFT, 0, movetoworkspace, 10" ];

  focusBinds = [
    # Vim-style bindings
    "${mod}, h, movefocus, l"
    "${mod}, j, movefocus, d"
    "${mod}, k, movefocus, u"
    "${mod}, l, movefocus, r"
    # Arrow key alternatives
    "${mod}, LEFT, movefocus, l"
    "${mod}, RIGHT, movefocus, r"
    "${mod}, UP, movefocus, u"
    "${mod}, DOWN, movefocus, d"
    # Workspace navigation
    "${mod}, comma, workspace, -1"
    "${mod}, period, workspace, +1"
    "${mod}, TAB, workspace, previous"
  ];

  swapBinds = [
    # Vim-style bindings
    "${mod} SHIFT, h, swapwindow, l"
    "${mod} SHIFT, j, swapwindow, d"
    "${mod} SHIFT, k, swapwindow, u"
    "${mod} SHIFT, l, swapwindow, r"
    # Arrow key alternatives
    "${mod} SHIFT, left, swapwindow, l"
    "${mod} SHIFT, right, swapwindow, r"
    "${mod} SHIFT, up, swapwindow, u"
    "${mod} SHIFT, down, swapwindow, d"
  ];

  resizeBinds = [
    # Standard resize bindings
    "${mod}, minus, resizeactive, -100 0"
    "${mod}, equal, resizeactive, 100 0"
    "${mod} SHIFT, minus, resizeactive, 0 -100"
    "${mod} SHIFT, equal, resizeactive, 0 100"
    # Vim-style directional resize
    "${mod} CTRL, h, resizeactive, -100 0"
    "${mod} CTRL, l, resizeactive, 100 0"
    "${mod} CTRL, k, resizeactive, 0 -100"
    "${mod} CTRL, j, resizeactive, 0 100"
  ];

  sessionBinds = [
    "${mod}, ESCAPE, exec, hyprlock"
    "${mod} SHIFT, ESCAPE, exit,"
    "${mod} CTRL, ESCAPE, exec, reboot"
    "${mod} SHIFT CTRL, ESCAPE, exec, systemctl poweroff"
  ];

  tilingBinds = [
    "${mod}, RETURN, exec, ghostty"
    "SUPER, SPACE, exec, walker"
    "${mod}, W, killactive"
    "${mod}, T, togglesplit" # Changed from J to avoid conflict with vim j
    "${mod}, O, exec, 1password"
    "${mod}, P, exec, spotify"
    "${mod} SHIFT, P, pseudo"
    "${mod}, V, togglefloating"
    "${mod}, F, fullscreen" # Simplified fullscreen binding
    "${mod} SHIFT, Plus, fullscreen"
    "${mod} SHIFT, SPACE, exec, pkill -SIGUSR1 waybar"
    "${mod}, S, togglespecialworkspace, magic"
    "${mod} SHIFT, S, movetoworkspace, special:magic"
    "${mod}, M, focuscurrentorlast" # Focus back-and-forth like aerospace
    "${mod}, B, workspace, name:b"
    "${mod}, Y, workspace, name:g"
    "${mod}, N, workspace, 1"
    "${mod}, C, exec, slack"
  ];

  # Group (tabbed) layout bindings - similar to i3's tabbed mode
  groupBinds = [
    "${mod}, G, togglegroup" # Create/destroy group
    "${mod}, bracketright, changegroupactive, f" # Next tab in group
    "${mod}, bracketleft, changegroupactive, b" # Previous tab in group
    "${mod} CTRL, G, moveoutofgroup" # Remove window from group
    "${mod} SHIFT, G, lockactivegroup, toggle" # Lock/unlock group
    # Move window into group in direction
    "${mod} CTRL SHIFT, h, moveintogroup, l" # Move into group left
    "${mod} CTRL SHIFT, j, moveintogroup, d" # Move into group down
    "${mod} CTRL SHIFT, k, moveintogroup, u" # Move into group up
    "${mod} CTRL SHIFT, l, moveintogroup, r" # Move into group right
  ];

  scrollBinds = [
    "${mod}, mouse_down, workspace, e+1"
    "${mod}, mouse_up, workspace, e-1"
  ];

  mouseBinds = [
    "${mod}, mouse:272, movewindow"
    "${mod}, mouse:273, resizewindow"
  ];

  monitorBinds = [
    "${mod} SHIFT, comma, movecurrentworkspacetomonitor, -1"
    "${mod} SHIFT, period, movecurrentworkspacetomonitor, +1"
  ];

  volumeBinds = [
    ",XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
    ",XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
    ",XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
    ",XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
  ];

  mediaBinds = [
    ", XF86AudioNext, exec, playerctl next"
    ", XF86AudioPause, exec, playerctl play-pause"
    ", XF86AudioPlay, exec, playerctl play-pause"
    ", XF86AudioPrev, exec, playerctl previous"
  ];

  hyprvoiceBinds = [
    "${mod}, R, exec, ${home}/.local/bin/hyprvoice toggle"
    "${mod} SHIFT, R, exec, ${home}/.local/bin/hyprvoice cancel"
  ];

  screenshotBinds = [
    "SUPER SHIFT, 4, exec, grimblast --notify copysave area ~/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png"
    "SUPER SHIFT, 3, exec, grimblast --notify copysave output ~/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png"
  ];

  keyboardBinds = [
    "${mod} SUPER, SPACE, exec, hyprctl switchxkblayout all next"
  ];

  extras = [
    "${mod} SUPER, m, exec, ${dotfiles}/bin/wake-monitors"
    "${mod} SHIFT, W, exec, ${cycleWallpaper}"
  ];
in
{
  wayland.windowManager.hyprland.settings = {
    bind = lib.concatLists [
      tilingBinds
      groupBinds
      focusBinds
      workspaceBinds
      moveWorkspaceBinds
      swapBinds
      resizeBinds
      sessionBinds
      scrollBinds
      monitorBinds
      hyprvoiceBinds
      screenshotBinds
      keyboardBinds
      extras
    ];

    bindm = mouseBinds;
    bindel = volumeBinds;
    bindl = mediaBinds;
  };
}
