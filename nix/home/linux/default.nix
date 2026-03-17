# Linux-specific Home Manager modules (both NixOS and standalone)
# Note: niri is opt-in via explicit imports (./niri, ./niri/switcher.nix)
# Note: xwayland-satellite is spawned on-demand by niri when X11 apps connect
{
  config,
  lib,
  dotfiles,
  ...
}:
let
  hmLib = lib.hm;
  linuxOnlySkills = [
    "wayvoice"
    "skill-eval"
  ];
in
{
  imports = [
    ./hyprlock.nix
    ./xremap.nix
  ];

  home.file.".config/wayvoice/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/wayvoice/config.toml";

  home.activation.linkLinuxOnlySkills = hmLib.dag.entryAfter [ "linkGeneration" ] ''
    repo=${lib.escapeShellArg dotfiles}
    skills_src="$repo/skills"

    link_skill() {
      base="$1"
      skill="$2"
      src="$skills_src/$skill"
      dst="$base/$skill"
      [ -d "$src" ] || return
      if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        return
      fi
      rm -rf "$dst"
      ln -s "$src" "$dst"
    }

    for skill in ${lib.concatStringsSep " " (map lib.escapeShellArg linuxOnlySkills)}; do
      link_skill "$HOME/.claude/skills" "$skill"
      link_skill "$HOME/.codex/skills" "$skill"
      link_skill "$HOME/.pi/agent/skills" "$skill"
    done
  '';
}
