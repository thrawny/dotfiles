{
  config,
  direnvAssets,
  homeSource,
  lib,
  ...
}:
let
  repoBacked = homeSource == "repo";
in
{
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    config.whitelist.prefix =
      lib.optionals repoBacked [
        "${config.home.homeDirectory}/dotfiles"
      ]
      ++ [
        "${config.home.homeDirectory}/code"
        "${config.home.homeDirectory}/work"
      ];
    inherit (direnvAssets) stdlib;
  };
}
