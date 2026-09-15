{ pkgs, ... }:

{
  imports = [
    ../../home/darwin/default.nix
  ];

  # terraform is BUSL-licensed. Setting nixpkgs.config makes Home Manager
  # re-import nixpkgs for this host; that is the price of the one package.
  nixpkgs.config.allowUnfree = true;

  home.packages = with pkgs; [
    terraform
    (google-cloud-sdk.withExtraComponents [ google-cloud-sdk.components.gke-gcloud-auth-plugin ])
    kubectx
    pyenv
    jira-cli-go
  ];
}
