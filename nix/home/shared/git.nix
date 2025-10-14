{
  config,
  dotfiles,
  ...
}:
{
  home.file.".gitconfig".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/git/gitconfig";
  home.file.".gitignoreglobal".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/git/gitignoreglobal";
}
