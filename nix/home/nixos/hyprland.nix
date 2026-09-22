# Hyprland home config. The compositor itself is enabled at the NixOS level
# (programs.hyprland in modules/desktop.nix). The config is pure Lua
# (hyprlang is deprecated since 0.55) and shipped as mutable symlinks:
# edit config/hypr/ and Hyprland reloads it; no `just switch` needed.
# ~/.config/hypr/hyprlock.conf stays home-manager generated (hyprlock.nix),
# which is why the files are linked individually rather than the whole dir.
{
  config,
  dotfiles,
  pkgs,
  ...
}:
let
  clipboard = pkgs.writeShellApplication {
    name = "shell-clipboard";
    runtimeInputs = [
      pkgs.cliphist
      pkgs.wl-clipboard
      pkgs.coreutils
    ];
    text = ''
      exec ${pkgs.bash}/bin/bash ${../../../bin/shell-clipboard} "$@"
    '';
  };
  clipboardWatcher = type: {
    Unit = {
      Description = "Record ${type} clipboard history for the desktop shell";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type ${type} --watch ${clipboard}/bin/shell-clipboard store";
      Restart = "on-failure";
      RestartSec = 2;
      UMask = "0077";
    };
    # Started by Hyprland, not Niri; stopped when the graphical session ends.
  };
in
{
  systemd.user.services = {
    shell-clipboard-text = clipboardWatcher "text";
    shell-clipboard-image = clipboardWatcher "image";
  };

  home.packages = [
    pkgs.cliphist
    clipboard
    pkgs.hyprshot
    pkgs.quickshell
    (pkgs.writeShellApplication {
      name = "dotfiles-launcher";
      runtimeInputs = [
        pkgs.quickshell
        pkgs.coreutils
      ];
      text = ''
        export DOTFILES_SHELL_DIR=${pkgs.lib.escapeShellArg "${dotfiles}/shell"}
        exec ${pkgs.bash}/bin/bash ${../../../bin/dotfiles-launcher} "$@"
      '';
    })
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
