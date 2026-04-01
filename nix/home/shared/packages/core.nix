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
    bash
    curl
    wget
    comma
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

    # Git
    gh
    lazygit
    git
    git-lfs

    # Languages
    nodejs_24
    python313
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
    pnpm
    biome
  ];
}
