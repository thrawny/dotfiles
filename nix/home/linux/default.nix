# Linux-specific Home Manager modules (both NixOS and standalone)
# Note: niri is opt-in via explicit imports (./niri, ./niri/dms.nix, ./niri/switcher.nix)
# Note: xwayland-satellite is spawned on-demand by niri when X11 apps connect
{
  imports = [
    ./xremap.nix
    ./hyprvoice.nix
  ];
}
