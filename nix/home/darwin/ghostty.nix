{ config, lib, ... }:
{
  # SSH sessions do not inherit Ghostty's TERMINFO environment variable.
  home.file.".terminfo/78/xterm-ghostty".source =
    config.lib.file.mkOutOfStoreSymlink "/Applications/Ghostty.app/Contents/Resources/terminfo/78/xterm-ghostty";

  # cmd+m belongs to the AppKit "Minimize" menu item, which Ghostty's keybind
  # system cannot touch, so the shortcut has to be stripped at the macOS level
  # for Herdr's last_pane binding to see the key. A key equivalent of NUL means
  # "no shortcut"; the menu item itself stays.
  home.activation.unbindGhosttyMinimize = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD /usr/bin/defaults write com.mitchellh.ghostty NSUserKeyEquivalents \
      -dict-add "Minimize" '\0'
  '';

  # Override ghostty settings for macOS
  programs.ghostty.settings = {
    font-size = lib.mkForce 14;
    font-thicken = true;
    font-thicken-strength = 50;
    window-padding-y = lib.mkForce 2;
    macos-option-as-alt = true;
  };
}
