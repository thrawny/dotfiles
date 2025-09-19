{ config, dotfiles, ... }:
{
  # Symlink the walker config files
  home.file.".config/walker/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/walker/config.toml";

  home.file.".config/walker/style.css".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/walker/style.css";
}