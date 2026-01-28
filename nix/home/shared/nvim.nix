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

    # LSPs, formatters, linters - available in Neovim's PATH
    extraPackages = with pkgs; [
      # LSPs
      gopls
      basedpyright
      lua-language-server
      rust-analyzer
      vtsls
      terraform-ls
      yaml-language-server
      nixd

      # Formatters/Linters
      golangci-lint
      ruff
      stylua
      selene
      biome
      taplo
      nixfmt
      statix

      # Required tools
      ripgrep
      fd
      gcc
      tree-sitter
    ];

  };
}
