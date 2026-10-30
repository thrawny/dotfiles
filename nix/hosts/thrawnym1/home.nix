{ pkgs, ... }:
{
  imports = [ ../../home/darwin ];

  home.packages = [ pkgs.nixos-rebuild ];

  # Dotfiles provisioning uses HTTPS URLs; this host authenticates GitHub via SSH.
  programs.git.settings."url \"git@github.com:thrawny/dotfiles.git\"".insteadOf =
    "https://github.com/thrawny/dotfiles.git";

  dotfiles.privateAgentSkills.enable = true;
  dotfiles.t3code.enable = true;
  dotfiles.t3code.port = 4773;
  dotfiles.t3code.httpsPort = 8445;
  dotfiles.openclawNode.enable = true;
  dotfiles.openclawNode.packages = [ pkgs.sonoscli ];
  dotfiles.openclawNode.host = "openclaw.tailf85bba.ts.net";
}
