{ lib, ... }:
let
  hmLib = lib.hm;
in
{
  # macOS system defaults and setup
  home.activation.setMacOSDefaults = hmLib.dag.entryAfter [ "writeBoundary" ] ''
    # Finder settings
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.finder AppleShowAllFiles -bool true
    $DRY_RUN_CMD /usr/bin/defaults write NSGlobalDomain AppleShowAllExtensions -bool true
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

    # Screenshot settings
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.screencapture type -string "png"
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.screencapture location ~/Screenshots

    # Swap the screenshot shortcuts so a bare cmd+shift+3/4 copies to the
    # clipboard and adding ctrl writes the file. Parameters are
    # (ascii, virtual key code, modifier mask): cmd+shift = 1179648,
    # cmd+ctrl+shift = 1441792. IDs 28/30 save to a file, 29/31 copy.
    # The trip through PlistBuddy is what keeps those numbers integers;
    # `defaults -dict-add` would store them as strings and macOS ignores those.
    hotkeys_plist=$(mktemp "''${TMPDIR:-/tmp}/symbolichotkeys.XXXXXX")
    /usr/bin/defaults export com.apple.symbolichotkeys "$hotkeys_plist"
    for hotkey in 28:51:20:1441792 29:51:20:1179648 30:52:21:1441792 31:52:21:1179648; do
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

    # Keyboard settings
    $DRY_RUN_CMD /usr/bin/defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
    $DRY_RUN_CMD /usr/bin/defaults write NSGlobalDomain KeyRepeat -int 2
    $DRY_RUN_CMD /usr/bin/defaults write NSGlobalDomain InitialKeyRepeat -int 10

    # Finder behavior
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.finder QuitMenuItem -bool true
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.finder DisableAllAnimations -bool true
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.finder NewWindowTargetPath -string "file://$HOME/Downloads/"
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.finder ShowStatusBar -bool true
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.finder ShowPathbar -bool true
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.finder WarnOnEmptyTrash -bool false

    # Show Library folder
    $DRY_RUN_CMD /usr/bin/chflags nohidden ~/Library 2>/dev/null || true

    # Dock settings
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.dock minimize-to-application -bool true
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.dock mru-spaces -bool false
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.dock autohide -bool true
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.dock show-recents -bool false

    # Software Update settings
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.SoftwareUpdate AutomaticDownload -int 1
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -int 1
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.commerce AutoUpdate -bool true

    # Menu bar clock format
    $DRY_RUN_CMD /usr/bin/defaults write com.apple.menuextra.clock DateFormat -string "yyyy-MM-dd HH:mm"

    echo "macOS defaults have been set. Restart Finder and Dock to see changes:"
    echo "  killall Finder Dock"
  '';

  # Create Screenshots directory
  home.activation.createScreenshotsDir = hmLib.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p "$HOME/Screenshots"
  '';
}
