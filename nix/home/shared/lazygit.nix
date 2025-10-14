{
  config,
  dotfiles,
  ...
}:
{
  xdg.configFile."lazygit".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/lazygit";
}
