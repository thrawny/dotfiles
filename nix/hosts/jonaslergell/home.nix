{ pkgs, ... }:

{
  imports = [
    ../../home/darwin/default.nix
    ./gita.nix
    ./herdr.nix
  ];

  # terraform is BUSL-licensed. Setting nixpkgs.config makes Home Manager
  # re-import nixpkgs for this host; that is the price of the one package.
  nixpkgs.config.allowUnfree = true;

  # Dev servers here run in Herdr tabs, not zmx. Pi keeps zmx-pi, its own
  # skill for background tasks.
  # A plugin loads its own language rules into every session here, and unslop
  # contradicts them on brackets and colons.
  dotfiles.agentSkills.disabled = [
    "zmx"
    "to-tickets"
    "unslop"
  ];
  dotfiles.agentInstructions.issueTracker.enable = false;
  dotfiles.agentInstructions.unslop.enable = false;

  home.packages = with pkgs; [
    terraform
    (google-cloud-sdk.withExtraComponents [ google-cloud-sdk.components.gke-gcloud-auth-plugin ])
    kubectx
    pyenv
    jira-cli-go
    ffmpeg
    atlas
  ];
}
