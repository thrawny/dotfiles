{ lib, ... }:
let
  baseInputConfig = import ./input-base.nix;
in
{
  wayland.windowManager.hyprland.settings = {
    input = lib.mkDefault baseInputConfig;
  };
}
