# Home Manager config for NixOS desktops
# Note: xwayland-satellite is spawned on-demand by niri when X11 apps connect
{
  pkgs,
  username,
  xremap-flake,
  ...
}:
{
  imports = [
    # Import all shared cross-platform modules
    ../shared

    # xremap home-manager module (from flake)
    xremap-flake.homeManagerModules.default
    ./xremap.nix

    # Niri window manager
    ./niri
    ./niri/switcher.nix

    # Hyprland (Lua config; session selectable at the greeter)
    ./hyprland.nix

    # Desktop modules
    ./hypridle.nix
    ./hyprlock.nix
    ./btop.nix
    ./mako.nix
    ./open-url.nix
    ./telegram.nix
    ./walker.nix
    ./waybar.nix
    ./gtk.nix
    ./viewers.nix
    ./voxtype.nix
  ];

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    stateVersion = "24.05";

    packages = with pkgs; [
      vesktop # Discord client with Wayland screen sharing support
    ];
  };
}
