{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # LSPs
    rust-analyzer
    gopls
    basedpyright
    pyright
    lua-language-server
    vtsls
    typescript-language-server
    terraform-ls
    yaml-language-server
    vscode-langservers-extracted
    nixd

    # Editor formatters/linters
    stylua
    selene
    taplo
    nixfmt
    statix

    # Diff/analysis tools
    difftastic
    dyff
    diffnav
    hyperfine
    usage
    cowsay

    # Build tools (treesitter)
    cmake
    tree-sitter

    # Shell
    tmux
  ];
}
