# Hyprland home config. The compositor itself is enabled at the NixOS level
# (programs.hyprland in modules/desktop.nix). The config is pure Lua
# (hyprlang is deprecated since 0.55) and shipped as mutable symlinks:
# edit config/hypr/, then `hyprctl reload` — no `just switch` needed.
# ~/.config/hypr/hyprlock.conf stays home-manager generated (hyprlock.nix),
# which is why the files are linked individually rather than the whole dir.
{
  config,
  dotfiles,
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.hyprshot
    pkgs.quickshell
    (pkgs.writeShellApplication {
      name = "dotfiles-bar";
      runtimeInputs = [
        pkgs.quickshell
        pkgs.procps
        pkgs.coreutils
      ];
      text = ''
        export DOTFILES_SHELL_DIR=${pkgs.lib.escapeShellArg "${dotfiles}/shell"}
        exec ${pkgs.bash}/bin/bash ${../../../bin/dotfiles-bar} "$@"
      '';
    })
  ];

  home.file = {
    ".config/hypr/hyprland.lua".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/hypr/hyprland.lua";
    ".config/hypr/lua".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/hypr/lua";
  };
}
