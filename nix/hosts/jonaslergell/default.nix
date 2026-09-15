{ pkgs, lib, ... }:

{
  imports = [
    ../../home/darwin/default.nix
  ];
  nixpkgs.config.allowUnfree = true;

  home.packages = with pkgs; [
    terraform
    (google-cloud-sdk.withExtraComponents [ google-cloud-sdk.components.gke-gcloud-auth-plugin ])
    kubectx
    pyenv
  ];
}
