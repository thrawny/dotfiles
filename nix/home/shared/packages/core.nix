{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # Core
    jq
    yq-go
    fzf
    ripgrep
    fd
    tree
    bat
    eza
    delta
    zoxide
    coreutils
    gnugrep
    gnused
    bashInteractive
    curl
    wget
    procps
    watch
    just
    direnv
    dnsutils
    netcat-gnu
    jwt-cli
    autossh
    watchexec
    ast-grep
    postgresql_17
    zsh
    starship
    gcc
    lsof
    actionlint

    # Document / image tools
    poppler-utils
    imagemagick

    # Git
    gh
    forgejo-cli
    lazygit
    git
    git-lfs

    # Languages
    nodejs_24
    (python314.withPackages (
      ps: with ps; [
        requests
        pillow
        pymupdf4llm
      ]
    ))
    uv
    ruff
    go
    golangci-lint
    gotestsum
    rustc
    cargo
    rustfmt
    clippy
    bun
    pnpm_11
    biome
  ];
}
