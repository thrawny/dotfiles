{
  config,
  dotfiles,
  ...
}:
{
  # Cursor configuration - Darwin uses ~/Library/Application Support/
  home.file."Library/Application Support/Cursor/User/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/cursor/settings.json";
  home.file."Library/Application Support/Cursor/User/keybindings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/cursor/keybindings.json";
}
