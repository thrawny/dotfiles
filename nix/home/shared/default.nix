{
  config,
  lib,
  pkgs,
  dotfiles,
  username,
  ...
}@args:
let
  hmLib = lib.hm;
  gitIdentity = {
    name = null;
    email = null;
  }
  // (args.gitIdentity or { });
  seedExample =
    example: destination:
    hmLib.dag.entryBefore [ "linkGeneration" ] ''
      repo=${lib.escapeShellArg dotfiles}
      example_path="$repo/${example}"
      dest_path="$repo/${destination}"
      if [ ! -s "$dest_path" ] && [ -e "$example_path" ]; then
        install -Dm0644 "$example_path" "$dest_path"
      fi
    '';
in
{
  imports = [
    # Shared cross-platform modules
    ./packages.nix
    ./direnv.nix
    ./git.nix
    ./ghostty.nix
    ./k9s.nix
    ./lazygit.nix
    ./npm.nix
    ./nvim.nix
    ./starship.nix
    ./tmux.nix
    ./zsh.nix
    ./mise.nix
  ];

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

  # Fuzzy search for Nix packages
  programs.nix-search-tv = {
    enable = true;
    settings = {
      indexes = [
        "nixpkgs"
        "home-manager"
        "nur"
        "nixos"
      ];
      update_interval = "168h";
    };
  };

  # Full nix-search-tv script with nix-shell, homepage, source navigation
  home.packages = [
    (pkgs.writeShellScriptBin "ns" (builtins.readFile "${pkgs.nix-search-tv.src}/nixpkgs.sh"))
  ];

  home = {
    stateVersion = "24.05";
    backupFileExtension = "bak";

    activation = {
      seedCodexConfig = seedExample "config/codex/config.example.toml" "config/codex/config.toml";
      seedClaudeSettings = seedExample "config/claude/settings.example.json" "config/claude/settings.json";
      seedCursorSettings = seedExample "config/cursor/settings.example.json" "config/cursor/settings.json";
    };

    file = {
      # Codex configuration
      ".codex".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex";

      # Claude configuration
      ".claude/commands".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/commands";
      ".claude/settings.json".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/settings.json";
      ".claude/agents".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/agents";
      ".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/skills";
      ".claude/rules".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/rules";
      ".claude/CLAUDE.md".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/CLAUDE-GLOBAL.md";

      # ccstatusline configuration
      ".config/ccstatusline/settings.json".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/claude/ccstatusline-settings.json";

      # Ensure .claude directory exists
      ".claude/.keep".text = "";

      ".gitconfig.local" = lib.mkIf (gitIdentity.name != null || gitIdentity.email != null) {
        text =
          lib.concatStringsSep "\n" (
            [ "[user]" ]
            ++ lib.optionals (gitIdentity.name != null) [ "\tname = ${gitIdentity.name}" ]
            ++ lib.optionals (gitIdentity.email != null) [ "\temail = ${gitIdentity.email}" ]
          )
          + "\n";
      };
    };
  };
}
