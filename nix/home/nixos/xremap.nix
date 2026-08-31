# xremap configuration for Linux systems
# Replaces keyd for key remapping with per-app exclusion support
#
# Two units, one per compositor, gated by ConditionEnvironment on
# XDG_CURRENT_DESKTOP (value-matched, so it self-corrects when switching
# sessions; socket vars like NIRI_SOCKET can linger in the user manager).
# xremap can only be built with one WM feature, so each unit runs the
# matching native build: withNiri for niri, xremap-hypr for Hyprland.
# The keymaps share everything except the Alt-a app-jump chords, which are
# nirius-based under niri and native Lua submaps under Hyprland.
{ pkgs, xremap-flake, ... }:
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
      name = "macOS-style shortcuts (exclude Ghostty)";
      application = {
        not = [
          "com.mitchellh.ghostty"
          "com.thrawny.GhosttyScratchpad"
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

  # niri-only: Hyprland handles these as native Lua submaps in config/hypr.
  appJumpChord = {
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
              "scratchpad-show-or-spawn"
              "--title"
              "^btop\\+\\+$"
              "--"
              "ghostty"
              "--title=btop++"
              "-e"
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
  };

  hyprConfigFile = (pkgs.formats.yaml { }).generate "xremap-hypr.yml" {
    modmap = sharedModmap;
    keymap = sharedKeymap;
  };

  xremapHypr = xremap-flake.packages.${pkgs.stdenv.hostPlatform.system}.xremap-hypr;
in
{
  services.xremap = {
    enable = true;
    withNiri = true;
    watch = true; # auto-detect newly connected devices (Bluetooth, USB hotplug)
    config = {
      modmap = sharedModmap;
      keymap = [ appJumpChord ] ++ sharedKeymap;
    };
  };

  systemd.user.services.xremap.Unit.ConditionEnvironment = "XDG_CURRENT_DESKTOP=niri";

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
