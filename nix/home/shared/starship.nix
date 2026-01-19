{
  config,
  dotfiles,
  ...
}:
{
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  # Use our custom config file via symlink
  xdg.configFile."starship.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/starship/starship.toml";
}
