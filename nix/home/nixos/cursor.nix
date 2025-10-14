{
  config,
  dotfiles,
  ...
}:
{
  # Cursor configuration for Linux - goes in ~/.config/Cursor/User/
  home.file.".config/Cursor/User/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/cursor/settings.json";
  home.file.".config/Cursor/User/keybindings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/cursor/keybindings.json";
}
