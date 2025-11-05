_: {
  # Override ghostty keybindings for NixOS
  # Add Mac-style super key bindings
  programs.ghostty.settings.keybind = [
    "shift+enter=text:\\n"
    "super+a=select_all"
    "super+c=copy_to_clipboard"
    "super+v=paste_from_clipboard"
  ];
}
