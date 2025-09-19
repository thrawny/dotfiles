# Keyd Per-Device Configuration Research

## Overview
Keyd allows configuring different keyboards independently, enabling different key mappings for built-in laptop keyboards vs external keyboards. This is useful when switching between keyboards with different physical layouts.

## Identifying Keyboard Device IDs

### Method 1: Using keyd monitor
```bash
sudo keyd -m
```
Press keys on each keyboard to see their device IDs and names.

### Method 2: List input devices
```bash
sudo keyd -l
```
Lists all available input devices with their IDs.

### Method 3: Check system devices
```bash
ls /dev/input/by-id/
ls /dev/input/by-path/
```

## Configuration Structure

### Basic Multi-Keyboard Setup
```nix
services.keyd = {
  enable = true;
  keyboards = {
    # Configuration for laptop's built-in keyboard
    laptop = {
      ids = ["0001:0002:0003:0004"];  # Replace with actual ID
      settings = {
        main = {
          # Swap keys for built-in keyboard
          leftalt = "leftcontrol";
          leftcontrol = "leftalt";
          capslock = "esc";
        };
      };
    };

    # Configuration for external Mac keyboard
    external = {
      ids = ["046d:c52b:*"];  # Can use wildcards
      settings = {
        main = {
          # No swapping needed for proper Mac keyboard
          capslock = "esc";  # Only remap caps lock
        };
      };
    };

    # Default fallback for any other keyboards
    default = {
      ids = ["*"];
      settings = {
        main = {
          capslock = "esc";
        };
      };
    };
  };
};
```

## Device ID Formats

### Full ID
```
0001:0002:0003:0004
```
Vendor:Product:Version:Bus

### Wildcards
```
046d:*           # All Logitech devices
*:c52b:*         # Specific product from any vendor
0001:0002:*      # Any version of specific device
```

### Multiple IDs per config
```nix
ids = [
  "046d:c52b:*",
  "046d:c534:*",
  "05ac:024f:*"   # Multiple Apple keyboard models
];
```

## Advanced Patterns

### Using device paths
```nix
ids = ["/dev/input/by-path/platform-i8042-serio-0-event-kbd"];
```

### Combining with environment detection
```nix
# In NixOS configuration
services.keyd = {
  enable = true;
  keyboards = let
    isLaptop = config.networking.hostName == "thinkpad";
  in {
    main = {
      ids = if isLaptop
        then ["AT Translated Set 2 keyboard"]
        else ["*"];
      settings = {
        # Different settings based on machine
      };
    };
  };
};
```

## Testing Configuration

### Verify config syntax
```bash
sudo keyd reload
```

### Check which config applies to a device
```bash
# Start monitor
sudo keyd -m
# Press keys to see which keyboard config is active
```

### Debug mode
```bash
sudo systemctl stop keyd
sudo keyd -d
```
Runs keyd in foreground with debug output.

## Common Device IDs

### Built-in laptop keyboards
- AT Translated Set 2 keyboard (most common)
- Apple Internal Keyboard / Trackpad
- ThinkPad Keyboard

### External keyboards
- Logitech: `046d:*`
- Apple Magic Keyboard: `05ac:024f:*` or `05ac:0267:*`
- Microsoft: `045e:*`
- Das Keyboard: `24f0:*`

## Troubleshooting

### Device not detected
1. Check if device appears in `sudo keyd -l`
2. Ensure keyd service has permissions: `sudo usermod -aG input keyd`
3. Check udev rules: `/etc/udev/rules.d/`

### Configuration not applying
1. More specific IDs take precedence over wildcards
2. First matching configuration wins
3. Default `["*"]` should be last

### Finding the right ID
```bash
# While keyd monitor is running
sudo keyd -m
# Type on the keyboard you want to identify
# Look for lines like:
# device added: 0001:0002:0003:0004 "Keyboard Name"
```

## Example: ThinkPad with Mac Keyboard

```nix
services.keyd = {
  enable = true;
  keyboards = {
    # ThinkPad's built-in keyboard - needs Alt/Ctrl swap
    thinkpad = {
      ids = ["AT Translated Set 2 keyboard"];
      settings = {
        main = {
          capslock = "esc";
          esc = "capslock";
          leftalt = "leftcontrol";
          leftcontrol = "leftalt";
          rightalt = "rightcontrol";
          rightcontrol = "rightalt";
        };
        shift = {
          "102nd" = "S-grave";  # ISO key fix
        };
      };
    };

    # Apple Magic Keyboard - already has correct layout
    apple = {
      ids = ["05ac:*"];  # All Apple keyboards
      settings = {
        main = {
          capslock = "esc";
          esc = "capslock";
          # No Alt/Ctrl swap needed
        };
      };
    };
  };
};
```

## References
- [Keyd GitHub](https://github.com/rvaiya/keyd)
- [Keyd Configuration Guide](https://github.com/rvaiya/keyd/blob/master/docs/config.md)
- [NixOS Keyd Module](https://search.nixos.org/options?query=services.keyd)