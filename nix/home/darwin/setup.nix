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
