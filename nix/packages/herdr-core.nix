{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "herdr-core";
  version = "0.1.15";

  src = fetchurl {
    url = "https://releases.herdr.dev/core/${finalAttrs.version}/herdr-core-linux-x86_64.tar.gz";
    hash = "sha256-77sTgto9UFPLIMYMFmpi7DTnPYKZl3+x9avtKN3sjWY=";
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  # The release is a static PIE; it needs no ELF interpreter or library patching.
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 herdr-core $out/bin/herdr-core
    ln -s herdr-core $out/bin/hc
    install -Dm644 LICENSE $out/share/licenses/herdr-core/LICENSE
    install -Dm644 THIRD-PARTY-NOTICES $out/share/licenses/herdr-core/THIRD-PARTY-NOTICES
    runHook postInstall
  '';

  meta = {
    description = "Persistent terminal runtime for coding agents";
    homepage = "https://herdr.dev/core/";
    license = lib.licenses.asl20;
    mainProgram = "hc";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
