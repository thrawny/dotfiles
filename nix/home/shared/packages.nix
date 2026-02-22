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
  zmxBinary = pkgs.stdenvNoCC.mkDerivation {
    pname = "zmx";
    version = "0.3.0";
    src = pkgs.fetchurl {
      url = "https://zmx.sh/a/zmx-0.3.0-linux-x86_64.tar.gz";
      sha256 = "0cnzvyj4afrjvl9w9zn2bd1v8sd0iixdgal1jzjs79mm3rcg3bzw";
    };
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
      tar -xzf "$src" -C "$out/bin"
      chmod 755 "$out/bin/zmx"
      runHook postInstall
    '';
    meta = {
      description = "Session persistence for terminal processes";
      homepage = "https://zmx.sh/";
      license = lib.licenses.mit;
      platforms = [ "x86_64-linux" ];
      mainProgram = "zmx";
    };
  };
in
{
  # Shared packages for both NixOS and Darwin
  home.packages =
    with pkgs;
    [
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
    ]
    ++ lib.optionals (system == "x86_64-linux") [
      zmxBinary
    ];
}
