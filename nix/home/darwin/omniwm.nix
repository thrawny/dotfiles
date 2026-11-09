{
  config,
  dotfiles,
  ...
}:
{
  # OmniWM window manager configuration
  home.file.".config/omniwm/settings.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/omniwm/settings.toml";
  home.file.".config/omniwm/shell/shell.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/omniwm/shell.toml";
}
