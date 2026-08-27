{
  lazy-nvim-nix,
  nvim-auto-save,
  nvim-baml-syntax,
  nvim-codediff,
  nvim-git-conflict,
  nvim-monokai-pro,
  nvim-tmux-navigator,
  pkgs,
  ...
}:
let
  nvim = import ../../lib/nvim-package.nix {
    inherit
      lazy-nvim-nix
      nvim-auto-save
      nvim-baml-syntax
      nvim-codediff
      nvim-git-conflict
      nvim-monokai-pro
      nvim-tmux-navigator
      pkgs
      ;
  };
in
{
  home.packages = [ nvim ];
}
