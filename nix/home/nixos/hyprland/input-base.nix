# Base input configuration shared across all hosts
{
  kb_layout = "au";
  follow_mouse = 1;
  sensitivity = 0; # Default 1:1 mouse movement
  accel_profile = "flat"; # No acceleration

  # Keyboard repeat configuration
  repeat_rate = 30; # Higher = faster repeat (default: 25)
  repeat_delay = 200; # Lower = quicker initial repeat (default: 600ms)

  touchpad = {
    disable_while_typing = false;
    natural_scroll = true;
    scroll_factor = 1.0;
    tap-to-click = true;
    clickfinger_behavior = true;
  };
}
