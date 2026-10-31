{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  herdr-core,
  libxcb,
  libxkbcommon,
  vulkan-loader,
  wayland,
  libglvnd,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "herdr-app";
  version = "0.1.10";

  src = fetchurl {
    url = "https://releases.herdr.dev/app/${finalAttrs.version}/herdr-app-linux-x86_64.tar.gz";
    hash = "sha256-re8P6rEpyE2N5NlReWKb8pfnaCLTDg1eacJirSMs4zo=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    copyDesktopItems
  ];
  buildInputs = [
    stdenv.cc.cc.lib
    libxcb
    libxkbcommon
  ];
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 herdr-app $out/bin/herdr-app
    # Keep the icon outside bin: upstream only enables its self-updater when
    # the icon is beside the executable. Nix owns updates for this install.
    install -Dm644 herdr-app.svg $out/share/icons/hicolor/scalable/apps/herdr-app.svg
    install -Dm644 LICENSE $out/share/licenses/herdr-app/LICENSE
    install -Dm644 THIRD-PARTY-NOTICES $out/share/licenses/herdr-app/THIRD-PARTY-NOTICES
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/herdr-app \
      --prefix PATH : ${lib.makeBinPath [ herdr-core ]} \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          vulkan-loader
          wayland
          libglvnd
        ]
      }
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "herdr-app";
      desktopName = "Herdr";
      comment = "Terminals and coding agents that keep running";
      exec = "herdr-app";
      icon = "herdr-app";
      categories = [ "Development" ];
      startupWMClass = "herdr-app";
    })
  ];

  meta = {
    description = "Native desktop app for terminals and coding agents";
    homepage = "https://herdr.dev/";
    license = lib.licenses.asl20;
    mainProgram = "herdr-app";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
