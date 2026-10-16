{
  stdenvNoCC,
  python3,
  systemd,
  libnotify,
}:
stdenvNoCC.mkDerivation {
  pname = "keepawake";
  version = "1";
  dontUnpack = true;
  installPhase = ''
    install -Dm755 ${../../bin/keepawake} $out/bin/keepawake
    install -Dm644 ${../../config/keepawake/config.example.toml} $out/share/keepawake/config.example.toml
    substituteInPlace $out/bin/keepawake \
      --replace-fail '#!/usr/bin/env python3' '#!${python3}/bin/python3' \
      --replace-fail '@busctl@' '${systemd}/bin/busctl' \
      --replace-fail '@notify_send@' '${libnotify}/bin/notify-send' \
      --replace-fail '@example@' "$out/share/keepawake/config.example.toml"
  '';
}
