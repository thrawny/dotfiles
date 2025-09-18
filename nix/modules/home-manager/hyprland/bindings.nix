{ lib, ... }:
let
  mod = "$mod";
  workspaceBinds = lib.map (n: "${mod}, ${builtins.toString n}, workspace, ${builtins.toString n}") [ 1 2 3 4 ];
  arrowFocusBinds = [
    "${mod}, LEFT, movefocus, l"
    "${mod}, RIGHT, movefocus, r"
    "${mod}, UP, movefocus, u"
    "${mod}, DOWN, movefocus, d"
  ];
  appBinds = [
    "${mod}, RETURN, exec, kitty"
    "${mod}, SPACE, exec, fuzzel"
  ];
  miscBinds = [
    "${mod}, Q, killactive"
    "${mod} SHIFT, Q, exit"
  ];
in
{
  wayland.windowManager.hyprland.settings.bind =
    appBinds
    ++ arrowFocusBinds
    ++ workspaceBinds
    ++ miscBinds;
}
