{
  rustPlatform,
  pkg-config,
  gtk4,
  gtk4-layer-shell,
  src,
}:
rustPlatform.buildRustPackage {
  pname = "agent-switch";
  version = "0.1.0";
  inherit src;
  cargoLock.lockFile = "${src}/Cargo.lock";
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    gtk4
    gtk4-layer-shell
  ];
}
