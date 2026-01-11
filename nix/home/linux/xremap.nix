# xremap configuration for Linux systems
# Replaces keyd for key remapping with per-app exclusion support
{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.xremap = {
    enable = true;
    withNiri = true;
    config = {
      # Key-to-key remapping (like xmodmap)
      modmap = [
        {
          name = "Global key remaps";
          remap = {
            "CapsLock" = "Esc";
          };
        }
      ];

      keymap = [
        # ISO keyboard tilde fix: Shift+102nd produces ~ instead of |
        {
          name = "ISO keyboard tilde fix";
          remap = {
            "Shift-KEY_102ND" = "Shift-Grave";
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

            # Undo/redo
            "Super-z" = "C-z";
            "Super-Shift-z" = "C-Shift-z";

            # Find/save/close/new tab
            "Super-f" = "C-f";
            "Super-s" = "C-s";
            "Super-w" = "C-w";
            "Super-t" = "C-t";

            # Navigation with Arrows (macOS-style)
            "Super-Left" = "Home";
            "Super-Right" = "End";
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
