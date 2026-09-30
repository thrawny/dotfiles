{ config, lib, ... }:
{
  # SSH sessions do not inherit Ghostty's TERMINFO environment variable.
  home.file.".terminfo/78/xterm-ghostty".source =
    config.lib.file.mkOutOfStoreSymlink "/Applications/Ghostty.app/Contents/Resources/terminfo/78/xterm-ghostty";

  # cmd+m belongs to the AppKit "Minimize" menu item, which Ghostty's keybind
  # system cannot touch, so the shortcut has to be stripped at the macOS level
  # for Herdr's last_pane binding to see the key. The "Zoom Split" menu item
  # holds cmd+shift+enter the same way, which Herdr needs for new_tab, and
  # "Hide Ghostty" holds cmd+h, which Herdr uses for previous_tab. A key
  # equivalent of NUL means "no shortcut"; the menu items themselves stay.
  home.activation.unbindGhosttyMenuShortcuts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD /usr/bin/defaults write com.mitchellh.ghostty NSUserKeyEquivalents \
      -dict-add "Minimize" '\0' "Zoom Split" '\0' "Hide Ghostty" '\0'
  '';

  # Override ghostty settings for macOS
  programs.ghostty.settings = {
    font-size = lib.mkForce 14;
    font-thicken = true;
    font-thicken-strength = 50;
    window-padding-y = lib.mkForce 2;
    macos-option-as-alt = true;
    # Alt+Q toggles a dropdown scratch terminal from any app, the same key as
    # the Hyprland scratchpad. Hiding it keeps the shell running until Ghostty
    # quits. A global keybind needs macOS Accessibility permission.
    quick-terminal-position = "center";
    # Width, then height, for the center position.
    quick-terminal-size = "80%,80%";
    quick-terminal-autohide = true;
    keybind = [ "global:alt+q=toggle_quick_terminal" ];
  };
}
