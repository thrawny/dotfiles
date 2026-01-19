{
  config,
  dotfiles,
  ...
}:
{
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  # Symlink only direnvrc, let HM manage the lib/ directory for nix-direnv
  xdg.configFile."direnv/direnvrc".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/direnv/direnvrc";
}
