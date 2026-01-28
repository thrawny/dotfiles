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

    # Minimal tools for headless - just enough for quick edits
    extraPackages = with pkgs; [
      ripgrep
      fd
      gcc
      tree-sitter
    ];

  };
}
