{
  pkgs,
  lib,
  zmx,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  zmxPkg = zmx.packages.${system}.zmx;
in
{
  home.packages = lib.optionals (builtins.hasAttr system zmx.packages) [
    zmxPkg
  ];
}
