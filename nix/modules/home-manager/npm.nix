{ config, dotfiles, ... }:
{
  home.file.".default-npm-packages".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/npm/default-packages";

  # Configure npm to use a writable directory for global packages
  home.file.".npmrc".text = ''
    prefix = ${config.home.homeDirectory}/.npm-global
  '';

  # Add npm global bin to PATH
  home.sessionVariables = {
    NPM_CONFIG_PREFIX = "${config.home.homeDirectory}/.npm-global";
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/.npm-global/bin"
  ];
}
