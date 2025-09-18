{ config, dotfiles, ... }:
{
  home.file.".tmux.conf".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/tmux/tmux.conf";
}
