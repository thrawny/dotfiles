{
  lazy-nvim-nix,
  nvim-auto-save,
  nvim-baml-syntax,
  nvim-codediff,
  nvim-git-conflict,
  nvim-monokai-pro,
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
      pkgs
      ;
  };
in
{
  home.packages = [ nvim ];
}
