{ lib, ... }:
{
  wayland.windowManager.hyprland.settings = {
    input = lib.mkDefault {
      kb_layout = "au";
      # kb_options removed - handled by keyd service for better compatibility
      follow_mouse = 1;
      sensitivity = 0;

      # Scroll configuration
      scroll_factor = 1.0; # Mouse scroll multiplier (default: 1.0, increase for more distance)

      touchpad = {
        disable_while_typing = false;
        natural_scroll = true;
        scroll_factor = 0.1;
        tap-to-click = true;
        clickfinger_behavior = true;
      };
    };
  };
}
