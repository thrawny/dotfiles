{ config, dotfiles, ... }:
{
  # Lazygit configuration - Darwin uses ~/Library/Application Support/
  home.file."Library/Application Support/lazygit".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/lazygit";
}