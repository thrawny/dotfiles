{ pkgs, ... }:
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
    git-lfs
    go
    golangci-lint
    tree
    procps
    zoxide
    bat
  ];
}