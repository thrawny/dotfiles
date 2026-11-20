# xremap configuration for Linux systems
# Replaces keyd for key remapping with per-app exclusion support
#
# One unit, gated by ConditionEnvironment on XDG_CURRENT_DESKTOP, runs the
# native xremap-hypr build. Hyprland handles the Alt-a app-jump chords as Lua
# submaps in config/hypr.
{
  pkgs,
  xremap-flake,
  ...
}:
let
  sharedModmap = [
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
      };
    }
  ];

  sharedKeymap = [
    # ISO keyboard: make < key behave like Mac (` and ~)
    {
      name = "ISO keyboard grave/tilde (Mac-style)";
      remap = {
        "KEY_102ND" = "Grave";
        "Shift-KEY_102ND" = "Shift-Grave";
      };
    }
    {
      name = "Right Alt Voxtype";
      remap = {
        "Alt_R-p".launch = [
          "voxtype"
          "record"
          "toggle"
        ];
        "Super_R-p".launch = [
          "voxtype"
          "record"
          "toggle"
        ];
      };
    }
    {
      name = "macOS-style shortcuts (exclude Ghostty and Herdr)";
      application = {
        not = [
          "com.mitchellh.ghostty"
          "com.thrawny.GhosttyScratchpad"
          "Ghostty"
          "herdr-app"
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

  hyprConfigFile = (pkgs.formats.yaml { }).generate "xremap-hypr.yml" {
    modmap = sharedModmap;
    keymap = sharedKeymap;
  };

  xremapHypr = xremap-flake.packages.${pkgs.stdenv.hostPlatform.system}.xremap-hypr;
in
{
  systemd.user.services.xremap-hypr = {
    Unit = {
      Description = "xremap (Hyprland variant)";
      # uwsm may or may not suffix the desktop name; accept both (|-prefixed
      # conditions of the same type are ORed).
      ConditionEnvironment = [
        "|XDG_CURRENT_DESKTOP=Hyprland"
        "|XDG_CURRENT_DESKTOP=Hyprland:uwsm"
      ];
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${xremapHypr}/bin/xremap --watch ${hyprConfigFile}";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
