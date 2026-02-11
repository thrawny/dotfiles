{
  config,
  dotfiles,
  pkgs,
  ...
}:
{
  xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/nvim";

  programs.neovim = {
    enable = true;
  };
}
