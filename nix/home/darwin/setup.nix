{ config, lib, ... }:
let
  hmLib = lib.hm;
  home = config.home.homeDirectory;
in
{
  # macOS system defaults. Home Manager writes each domain with
  # `defaults import`, which keeps the keys not listed here.
  targets.darwin.defaults = {
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      ApplePressAndHoldEnabled = false;
      KeyRepeat = 2;
      InitialKeyRepeat = 10;
    };

    "com.apple.desktopservices" = {
      DSDontWriteNetworkStores = true;
      DSDontWriteUSBStores = true;
    };

    "com.apple.screencapture" = {
      type = "png";
      location = "${home}/Screenshots";
    };

    # Pressing fn (globe) does nothing, instead of changing the input source.
    "com.apple.HIToolbox".AppleFnUsageType = 0;

    "com.apple.finder" = {
      AppleShowAllFiles = true;
      QuitMenuItem = true;
      DisableAllAnimations = true;
      NewWindowTargetPath = "file://${home}/Downloads/";
      ShowStatusBar = true;
      ShowPathbar = true;
      WarnOnEmptyTrash = false;
    };

    "com.apple.dock" = {
      minimize-to-application = true;
      mru-spaces = false;
      autohide = true;
      show-recents = false;
    };

    "com.apple.SoftwareUpdate" = {
      AutomaticCheckEnabled = true;
      ScheduleFrequency = 1;
      AutomaticDownload = 1;
      CriticalUpdateInstall = 1;
    };
    "com.apple.commerce".AutoUpdate = true;

    "com.apple.menuextra.clock".DateFormat = "yyyy-MM-dd HH:mm";
  }
  # Trackpad: three fingers drag, so swipes between spaces and
  # Mission Control move to four fingers. The built-in and Bluetooth
  # trackpads read separate domains.
  //
    lib.genAttrs
      [ "com.apple.AppleMultitouchTrackpad" "com.apple.driver.AppleBluetoothMultitouch.trackpad" ]
      (_: {
        TrackpadThreeFingerDrag = 1;
        TrackpadThreeFingerHorizSwipeGesture = 0;
        TrackpadThreeFingerVertSwipeGesture = 0;
        TrackpadFourFingerHorizSwipeGesture = 2;
        TrackpadFourFingerVertSwipeGesture = 2;
      });

  # Settings a defaults option cannot express. Runs after setDarwinDefaults
  # so activateSettings also picks up the keyboard settings.
  home.activation.setMacOSDefaults = hmLib.dag.entryAfter [ "writeBoundary" "setDarwinDefaults" ] ''
    # Swap the screenshot shortcuts so a bare cmd+shift+3/4 copies to the
    # clipboard and adding ctrl writes the file. Parameters are
    # (ascii, virtual key code, modifier mask): cmd+shift = 1179648,
    # cmd+ctrl+shift = 1441792. IDs 28/30 save to a file, 29/31 copy.
    # The trip through PlistBuddy is what keeps those numbers integers;
    # `defaults -dict-add` would store them as strings and macOS ignores those.
    # ID 60 selects the previous input source: cmd+option+space = 1572864.
    # That takes the combo from ID 65 (Finder search window), so 65 is disabled.
    hotkeys_plist=$(mktemp "''${TMPDIR:-/tmp}/symbolichotkeys.XXXXXX")
    /usr/bin/defaults export com.apple.symbolichotkeys "$hotkeys_plist"
    /usr/libexec/PlistBuddy "$hotkeys_plist" \
      -c "Delete :AppleSymbolicHotKeys:65" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy "$hotkeys_plist" \
      -c "Add :AppleSymbolicHotKeys:65 dict" \
      -c "Add :AppleSymbolicHotKeys:65:enabled bool false" >/dev/null
    for hotkey in 28:51:20:1441792 29:51:20:1179648 30:52:21:1441792 31:52:21:1179648 60:32:49:1572864; do
      IFS=: read -r id ascii keycode modifiers <<<"$hotkey"
      /usr/libexec/PlistBuddy "$hotkeys_plist" \
        -c "Delete :AppleSymbolicHotKeys:$id" >/dev/null 2>&1 || true
      /usr/libexec/PlistBuddy "$hotkeys_plist" \
        -c "Add :AppleSymbolicHotKeys:$id dict" \
        -c "Add :AppleSymbolicHotKeys:$id:enabled integer 1" \
        -c "Add :AppleSymbolicHotKeys:$id:value dict" \
        -c "Add :AppleSymbolicHotKeys:$id:value:type string standard" \
        -c "Add :AppleSymbolicHotKeys:$id:value:parameters array" \
        -c "Add :AppleSymbolicHotKeys:$id:value:parameters:0 integer $ascii" \
        -c "Add :AppleSymbolicHotKeys:$id:value:parameters:1 integer $keycode" \
        -c "Add :AppleSymbolicHotKeys:$id:value:parameters:2 integer $modifiers" \
        >/dev/null
    done
    $DRY_RUN_CMD /usr/bin/defaults import com.apple.symbolichotkeys "$hotkeys_plist"
    rm -f "$hotkeys_plist"
    # Without this the shortcuts only change after a logout.
    $DRY_RUN_CMD /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u

    # Show Library folder
    $DRY_RUN_CMD /usr/bin/chflags nohidden ~/Library 2>/dev/null || true

    echo "macOS defaults have been set. Restart Finder and Dock to see changes:"
    echo "  killall Finder Dock"
  '';

  # Create Screenshots directory
  home.activation.createScreenshotsDir = hmLib.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p "$HOME/Screenshots"
  '';
}
