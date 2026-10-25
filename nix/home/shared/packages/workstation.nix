{
  lib,
  pkgs,
  thrawny-pkgs,
  ...
}:
{
  home.packages =
    with pkgs;
    [
      # LSPs
      rust-analyzer
      gopls
      lua-language-server
      vtsls
      typescript-language-server
      terraform-ls
      yaml-language-server
      helm-ls
      vscode-json-languageserver
      nixd

      # Editor formatters/linters
      stylua
      selene
      taplo
      nixfmt
      statix
      deadnix

      # Nix maintenance
      nvd
      cachix

      # Diff/analysis tools
      difftastic
      dyff
      hyperfine
      usage
      cowsay

      # Diagrams
      d2

      # Build tools
      cmake
      tree-sitter
      pkg-config

    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
      # Linux's shared preview host supplies its broker-wrapped system package.
      thrawny-pkgs.packages.${pkgs.stdenv.hostPlatform.system}.portless
    ];
}
