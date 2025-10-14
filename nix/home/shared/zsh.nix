{
  config,
  dotfiles,
  ...
}:
{
  home.file.".zshrc".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/zsh/zshrc";
}
