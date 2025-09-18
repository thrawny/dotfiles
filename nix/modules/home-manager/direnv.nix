{ config, dotfiles, ... }:
{
  xdg.configFile."direnv".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/direnv";
}
