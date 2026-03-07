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
  kubectl134 =
    if pkgs.stdenv.isLinux && pkgs.stdenv.hostPlatform.isx86_64 then
      pkgs.stdenvNoCC.mkDerivation {
        pname = "kubectl";
        version = "1.34.5";
        src = pkgs.fetchurl {
          url = "https://dl.k8s.io/release/v1.34.5/bin/linux/amd64/kubectl";
          hash = "sha256-ahfdg4d4OzFEplU1440Cw1ECfpcY6jSmw2BHbLJtKLs=";
        };
        dontUnpack = true;
        installPhase = ''
          install -Dm755 "$src" "$out/bin/kubectl"
        '';
      }
    else
      pkgs.kubectl;
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
    kubectl134
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
  ]
  ++ lib.optionals stdenv.isLinux [
    claudePkgs.claude-code
    llmPkgs.codex
    llmPkgs.pi
  ];
}
