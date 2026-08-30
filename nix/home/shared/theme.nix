# Provides the central theme (nix/themes/monokai.json) to Home Manager
# modules as the `theme`/`themeLib` args, and publishes a runtime copy for
# mutable consumers (Pi extensions, Neovim's fallback path).
{ lib, ... }:
let
  themeLib = import ../../lib/theme.nix { inherit lib; };
  theme = themeLib.loadTheme ../../themes/monokai.json;
in
{
  _module.args = {
    inherit theme themeLib;
  };

  xdg.configFile."dotfiles/theme.json".text = builtins.toJSON theme;
}
