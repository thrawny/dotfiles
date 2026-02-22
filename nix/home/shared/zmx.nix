{
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  zmxBinary = pkgs.stdenvNoCC.mkDerivation {
    pname = "zmx";
    version = "0.4.0";
    src = pkgs.fetchurl {
      url = "https://zmx.sh/a/zmx-0.4.0-linux-x86_64.tar.gz";
      sha256 = "sha256-+ubSJrmPjf7qCXb/L57xYyzw6f2ky5IdCPKunr2Vo3g=";
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
  home.packages = lib.optionals (system == "x86_64-linux") [
    zmxBinary
  ];
}
