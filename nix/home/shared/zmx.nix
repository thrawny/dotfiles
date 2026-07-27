{
  config,
  pkgs,
  lib,
  zmx,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  zmxPkg = zmx.packages.${system}.zmx-main;
in
{
  home = {
    packages = lib.optionals (builtins.hasAttr system zmx.packages) [
      zmxPkg
    ];

    sessionVariables = {
      # Run tasks with the configured zsh; it preserves the POSIX `$?` that
      # zmx's exit-code tracking scrapes.
      ZMX_TASK_SHELL = lib.getExe config.programs.zsh.package;
    };
  };
}
