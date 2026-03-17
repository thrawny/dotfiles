# Linux-specific Home Manager modules (both NixOS and standalone)
# Note: niri is opt-in via explicit imports (./niri, ./niri/switcher.nix)
# Note: xwayland-satellite is spawned on-demand by niri when X11 apps connect
{
  config,
  dotfiles,
  ...
}:
{
  imports = [
    ./hyprlock.nix
    ./xremap.nix
  ];

  home.file.".config/wayvoice/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/wayvoice/config.toml";
}
