{
  config,
  dotfiles,
  ...
}:
{
  # Aerospace window manager configuration
  home.file.".aerospace.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/aerospace/aerospace.toml";
}
