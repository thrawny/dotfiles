{ config, dotfiles, ... }:
{
  xdg.configFile."k9s".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/k9s";
}
