{ lib, ... }:
let
  mod = "$mod";

  workspaceDigits = lib.range 1 9;

  workspaceBinds =
    (map (n: "${mod}, ${builtins.toString n}, workspace, ${builtins.toString n}") workspaceDigits)
    ++ [ "${mod}, 0, workspace, 10" ];

  moveWorkspaceBinds =
    (map (n: "${mod} SHIFT, ${builtins.toString n}, movetoworkspace, ${builtins.toString n}") workspaceDigits)
    ++ [ "${mod} SHIFT, 0, movetoworkspace, 10" ];

  focusBinds = [
    "${mod}, LEFT, movefocus, l"
    "${mod}, RIGHT, movefocus, r"
    "${mod}, UP, movefocus, u"
    "${mod}, DOWN, movefocus, d"
    "${mod}, comma, workspace, -1"
    "${mod}, period, workspace, +1"
  ];

  swapBinds = [
    "${mod} SHIFT, left, swapwindow, l"
    "${mod} SHIFT, right, swapwindow, r"
    "${mod} SHIFT, up, swapwindow, u"
    "${mod} SHIFT, down, swapwindow, d"
  ];

  resizeBinds = [
    "${mod}, minus, resizeactive, -100 0"
    "${mod}, equal, resizeactive, 100 0"
    "${mod} SHIFT, minus, resizeactive, 0 -100"
    "${mod} SHIFT, equal, resizeactive, 0 100"
  ];

  sessionBinds = [
    "${mod}, ESCAPE, exec, hyprlock"
    "${mod} SHIFT, ESCAPE, exit,"
    "${mod} CTRL, ESCAPE, exec, reboot"
    "${mod} SHIFT CTRL, ESCAPE, exec, systemctl poweroff"
  ];

  tilingBinds = [
    "${mod}, RETURN, exec, ghostty"
    "${mod}, SPACE, exec, fuzzel"
    "${mod}, W, killactive"
    "${mod}, J, togglesplit"
    "${mod}, P, pseudo"
    "${mod}, V, togglefloating"
    "${mod} SHIFT, Plus, fullscreen"
    "${mod} SHIFT, SPACE, exec, pkill -SIGUSR1 waybar"
    "${mod}, S, togglespecialworkspace, magic"
    "${mod} SHIFT, S, movetoworkspace, special:magic"
  ];

  scrollBinds = [
    "${mod}, mouse_down, workspace, e+1"
    "${mod}, mouse_up, workspace, e-1"
  ];

  mouseBinds = [
    "${mod}, mouse:272, movewindow"
    "${mod}, mouse:273, resizewindow"
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
in
{
  wayland.windowManager.hyprland.settings = {
    bind = lib.concatLists [
      tilingBinds
      focusBinds
      workspaceBinds
      moveWorkspaceBinds
      swapBinds
      resizeBinds
      sessionBinds
      scrollBinds
    ];

    bindm = mouseBinds;
    bindel = volumeBinds;
    bindl = mediaBinds;
  };
}
