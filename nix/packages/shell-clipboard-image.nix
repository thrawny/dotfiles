{
  stdenvNoCC,
  python3,
  cliphist,
  wl-clipboard,
}:
stdenvNoCC.mkDerivation {
  pname = "shell-clipboard-image";
  version = "1";
  dontUnpack = true;
  installPhase = ''
    install -Dm755 ${../../bin/shell-clipboard-image} $out/bin/shell-clipboard-image
    substituteInPlace $out/bin/shell-clipboard-image \
      --replace-fail '#!/usr/bin/env python3' '#!${python3}/bin/python3' \
      --replace-fail '@cliphist@' '${cliphist}/bin/cliphist' \
      --replace-fail '@wl_copy@' '${wl-clipboard}/bin/wl-copy'
  '';
}
