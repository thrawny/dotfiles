{ lib, ... }:
{
  wayland.windowManager.hyprland.settings = {
    input = lib.mkDefault {
      kb_layout = "au";
      # kb_options removed - handled by keyd service for better compatibility
      follow_mouse = 1;
      sensitivity = 0;

      # Keyboard repeat configuration
      repeat_rate = 30; # Higher = faster repeat (default: 25)
      repeat_delay = 200; # Lower = quicker initial repeat (default: 600ms)

      # Scroll configuration
      scroll_factor = 0.8; # Mouse scroll multiplier (default: 1.0, increase for more distance)

      touchpad = {
        disable_while_typing = false;
        natural_scroll = true;
        scroll_factor = 1.0;
        tap-to-click = true;
        clickfinger_behavior = true;
      };
    };
  };
}
