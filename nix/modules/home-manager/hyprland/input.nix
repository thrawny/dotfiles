{ lib, ... }:
{
  wayland.windowManager.hyprland.settings = {
    input = lib.mkDefault {
      kb_layout = "au";
      # kb_options removed - handled by keyd service for better compatibility
      follow_mouse = 1;
      sensitivity = 0;
      touchpad.natural_scroll = true;
    };
  };
}
