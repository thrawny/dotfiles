{
  homeSource,
  dotfiles,
  lib,
  pkgs,
  username,
  ...
}:
{
  imports = [
    ../shared/home-base.nix
    ../shared/packages.nix
    ../shared/btop.nix
    ../shared/direnv.nix
    ../shared/git.nix
    ../shared/k9s.nix
    ../shared/lazygit.nix
    ../shared/npm.nix
    ../shared/nvim.nix
    ../shared/starship.nix
    ../shared/tmux.nix
    ../shared/zsh.nix
    ../shared/zmx.nix
  ];

  programs.home-manager.enable = true;

  home = {
    inherit username;
    homeDirectory = "/home/${username}";

    packages = with pkgs; [
      ncurses
      (lib.hiPrio ghostty.terminfo)
    ];

    sessionVariables = {
      NVIM_HEADLESS = "1";
      COLORTERM = "truecolor";
    }
    // lib.optionalAttrs (homeSource == "store") {
      NVIM_STORE_CONFIG = "1";
    };

    activation = lib.optionalAttrs (homeSource == "repo") {
      seedClaudeSettings = lib.mkForce (
        lib.hm.dag.entryBefore [ "linkGeneration" ] ''
          repo=${lib.escapeShellArg dotfiles}
          example_path="$repo/config/claude/settings.example.json"
          dest_path="$repo/config/claude/settings.json"
          if [ ! -s "$dest_path" ] && [ -e "$example_path" ]; then
            ${pkgs.jq}/bin/jq 'del(.hooks, .enabledPlugins)' "$example_path" > "$dest_path"
            chmod 0644 "$dest_path"
          fi
        ''
      );
    };
  };
}
