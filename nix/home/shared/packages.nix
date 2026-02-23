{
  pkgs,
  lib,
  claude-code-nix,
  llm-agents,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  claudePkgs = claude-code-nix.packages.${system};
  llmPkgs = llm-agents.packages.${system};
in
{
  # Shared packages for both NixOS and Darwin
  home.packages = with pkgs; [
    nodejs_24
    python313
    starship
    uv
    gh
    lazygit
    jq
    yq-go
    fzf
    delta
    difftastic
    dyff
    git-lfs
    go
    golangci-lint
    gotestsum
    rustc
    cargo
    rustfmt
    clippy
    rust-analyzer
    tree
    procps
    zoxide
    bat
    biome
    direnv
    pnpm
    ripgrep
    tmux
    git
    zsh
    awscli2
    bash
    bun
    coreutils
    curl
    gnugrep
    gnused
    k9s
    kind
    cowsay
    watch
    postgresql_17
    ruff
    tree-sitter
    gcc
    cmake
    wget
    usage
    fd
    watchexec
    ast-grep
    hyperfine
    eza
    just
    autossh
    kustomize
    kubernetes-helm
    netcat-gnu
    jwt-cli
    zig

    # LSPs
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

    # Formatters/Linters
    stylua
    selene
    taplo
    nixfmt
    statix

    # AI tools
    (if stdenv.isDarwin then claudePkgs.claude-code else claudePkgs.claude-code-node)
    llmPkgs.codex
    llmPkgs.pi
  ];
}
