{
  config,
  dotfiles,
  ...
}:
{
  programs.mise = {
    enable = true;
    enableZshIntegration = false;
  };

  xdg.configFile."mise".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/mise";
}
