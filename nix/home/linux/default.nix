# Linux-specific Home Manager modules (both NixOS and standalone)
# Note: niri is opt-in via explicit imports (./niri, ./niri/dms.nix, ./niri/switcher.nix)
{
  imports = [
    ./xremap.nix
    ./hyprvoice.nix
  ];
}
