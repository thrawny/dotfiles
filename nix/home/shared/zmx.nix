{
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  zmxBinary = pkgs.stdenvNoCC.mkDerivation {
    pname = "zmx";
    version = "0.4.1";
    nativeBuildInputs = [ pkgs.installShellFiles ];
    src = pkgs.fetchurl {
      url = "https://zmx.sh/a/zmx-0.4.1-linux-x86_64.tar.gz";
      sha256 = "sha256-6bZbakDdXIj5toN2oFoOzGrHfuu7pE8WKfTbjoO2Eag=";
    };
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
      tar -xzf "$src" -C "$out/bin"
      chmod 755 "$out/bin/zmx"

      echo '#compdef zmx' > _zmx
      "$out/bin/zmx" completions zsh >> _zmx
      installShellCompletion --zsh _zmx
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
