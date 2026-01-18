# Niri project switcher (Rust GTK4 app)
# Adds niri-switcher package and startup daemon
{ pkgs, self, ... }:
let
  inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) niri-switcher;
in
{
  home.packages = [ niri-switcher ];

  programs.niri.settings = {
    spawn-at-startup = [
      { command = [ "niri-switcher" ]; }
    ];

    binds = {
      "Mod+S" = {
        action.spawn = [
          "niri-switcher"
          "--toggle"
        ];
        hotkey-overlay.title = "Project Switcher";
      };
    };
  };
}
