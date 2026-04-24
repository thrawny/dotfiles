# Linux-specific Home Manager modules (both NixOS and standalone)
# Note: niri is opt-in via explicit imports (./niri, ./niri/switcher.nix)
# Note: xwayland-satellite is spawned on-demand by niri when X11 apps connect
{
  config,
  linuxOnlySkills,
  dotfiles,
  skillFiles,
  ...
}:
{
  imports = [
    ./hyprlock.nix
    ./xremap.nix
  ];

  home.file =
    skillFiles ".claude/skills" linuxOnlySkills
    // skillFiles ".pi/agent/skills" linuxOnlySkills
    // skillFiles ".codex/skills" linuxOnlySkills
    // {
      ".config/wayvoice/config.toml".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/wayvoice/config.toml";
    };
}
