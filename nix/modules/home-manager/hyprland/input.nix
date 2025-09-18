{ lib, ... }:
{
  wayland.windowManager.hyprland.settings = {
    input = lib.mkDefault {
      kb_layout = "au";
      kb_options = "caps:swapescape";
      follow_mouse = 1;
      sensitivity = 0;
      touchpad.natural_scroll = false;
    };

    gestures = lib.mkDefault {
      workspace_swipe = false;
    };
  };
}
