{ config, dotfiles, ... }:
{
  home.file.".default-npm-packages".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/npm/default-packages";
}
