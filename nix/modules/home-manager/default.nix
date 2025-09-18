{ lib, pkgs, dotfiles, username, theme, ... }@args:
let
  hmLib = lib.hm;
  gitIdentity = { name = null; email = null; } // (args.gitIdentity or { });
  seedExample = example: destination:
    hmLib.dag.entryBefore [ "linkGeneration" ] ''
      repo=${lib.escapeShellArg dotfiles}
      example_path="$repo/${example}"
      dest_path="$repo/${destination}"
      if [ ! -s "$dest_path" ] && [ -e "$example_path" ]; then
        install -Dm0644 "$example_path" "$dest_path"
      fi
    '';
in {
  imports = [
    ./direnv.nix
    ./git.nix
    ./ghostty.nix
    ./hyprland/default.nix
    ./hypridle.nix
    ./hyprlock.nix
    ./hyprpaper.nix
    ./k9s.nix
    ./mako.nix
    ./nvim.nix
    ./npm.nix
    ./starship.nix
    ./tmux.nix
    ./waybar.nix
    ./zsh.nix
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "24.05";

  home.packages = with pkgs; [
    nodejs_24
    python313
    starship
    uv
    gh
  ];

  home.activation.seedClaudeSettings =
    seedExample "config/claude/settings.example.json" "config/claude/settings.json";
  home.activation.seedCursorSettings =
    seedExample "config/cursor/settings.example.json" "config/cursor/settings.json";

  home.file.".gitconfig.local" = lib.mkIf (gitIdentity.name != null || gitIdentity.email != null) {
    text = lib.concatStringsSep "\n" (
      [ "[user]" ]
      ++ lib.optionals (gitIdentity.name != null) [ "\tname = ${gitIdentity.name}" ]
      ++ lib.optionals (gitIdentity.email != null) [ "\temail = ${gitIdentity.email}" ]
    ) + "\n";
  };
}
