{ config, dotfiles, ... }:
{
  home.file.".default-npm-packages".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/npm/default-packages";

  # Configure npm to use a writable directory for global packages
  home.file.".npmrc".text = ''
    prefix = ${config.home.homeDirectory}/.npm-global
  '';
}
