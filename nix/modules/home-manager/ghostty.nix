{ config, dotfiles, ... }:
{
  xdg.configFile."ghostty".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/ghostty";
}
