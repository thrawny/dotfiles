{ config, dotfiles, ... }:
{
  # Starship prompt is loaded via zshrc; we only link the config file.
  xdg.configFile."starship.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/starship/starship.toml";
}
