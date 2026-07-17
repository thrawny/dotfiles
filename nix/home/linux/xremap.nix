# xremap configuration for Linux systems
# Replaces keyd for key remapping with per-app exclusion support
_: {
  services.xremap = {
    enable = true;
    withNiri = true;
    watch = true; # auto-detect newly connected devices (Bluetooth, USB hotplug)
    config = {
      # Key-to-key remapping (like xmodmap)
      modmap = [
        {
          name = "Built-in keyboard Alt/Super swap";
          device.only = [ "AT Translated Set 2 keyboard" ];
          remap = {
            "Alt_L" = "Super_L";
            "Super_L" = "Alt_L";
          };
        }
        {
          name = "Global key remaps";
          remap = {
            "CapsLock" = "Esc";
            "Shift_R" = {
              skip_key_event = true;
              press = [
                {
                  launch = [
                    "wayvoice-route"
                  ];
                }
              ];
              release = [
                {
                  launch = [
                    "wayvoice-route"
                  ];
                }
              ];
            };
          };
        }
      ];

      keymap = [
        # ISO keyboard: make < key behave like Mac (` and ~)
        {
          name = "ISO keyboard grave/tilde (Mac-style)";
          remap = {
            "KEY_102ND" = "Grave";
            "Shift-KEY_102ND" = "Shift-Grave";
          };
        }
        {
          name = "App jump chord (Alt-a prefix)";
          remap = {
            "Alt-a" = {
              remap = {
                "a" = {
                  launch = [
                    "nirius"
                    "focus"
                    "--title"
                    "k9s"
                  ];
                };
                "s" = {
                  launch = [
                    "nirius"
                    "focus"
                    "--app-id"
                    "(?i)slack"
                  ];
                };
                "d" = {
                  launch = [
                    "nirius"
                    "focus"
                    "--title"
                    "Microsoft Teams"
                  ];
                };
                "b" = {
                  launch = [
                    "nirius"
                    "focus"
                    "--title"
                    "btop"
                  ];
                };
                "z" = {
                  launch = [
                    "nirius"
                    "focus"
                    "--title"
                    "(?i)discord"
                  ];
                };
                "t" = {
                  launch = [
                    "nirius"
                    "focus"
                    "--app-id"
                    "org.telegram.desktop"
                  ];
                };
              };
              timeout_millis = 1000;
            };
          };
        }
        {
          name = "macOS-style shortcuts (exclude Ghostty)";
          application = {
            not = [
              "com.mitchellh.ghostty"
              "Ghostty"
            ];
          };
          remap = {
            # Copy/paste/cut/select all
            "Super-a" = "C-a";
            "Super-c" = "C-c";
            "Super-v" = "C-v";
            "Super-x" = "C-x";
            "Super-r" = "C-r";

            # Undo/redo
            "Super-z" = "C-z";
            "Super-Shift-z" = "C-Shift-z";

            # Find/save/close/new tab
            "Super-f" = "C-f";
            "Super-s" = "C-s";
            "Super-w" = "C-w";
            "Super-t" = "C-t";
            "Super-Alt-i" = "C-Shift-i";

            # Navigation with Arrows (macOS-style)
            "Super-Up" = "C-Home";
            "Super-Down" = "C-End";

            # Text selection with Shift+Arrows
            "Super-Shift-Left" = "Shift-Home";
            "Super-Shift-Right" = "Shift-End";
            "Super-Shift-Up" = "C-Shift-Home";
            "Super-Shift-Down" = "C-Shift-End";
          };
        }
      ];
    };
  };
}
