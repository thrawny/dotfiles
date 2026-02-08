{
  lib,
  pkgs,
  username,
  dotfiles,
  config,
  ...
}:
{
  imports = [
    # Shared home config (sessionPath, file symlinks, activation scripts)
    ../shared/home-base.nix

    # CLI-safe shared modules only (no ghostty/GUI)
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
  ];

  programs.home-manager.enable = true;

  home = {
    inherit username;
    homeDirectory = "/home/${username}";

    packages = with pkgs; [
      # Terminfo for SSH compatibility
      ncurses
      (lib.hiPrio ghostty.terminfo)
    ];

    sessionVariables = {
      NVIM_HEADLESS = "1";
      COLORTERM = "truecolor";
    };

    # Override seed to strip hooks (bash-validator, agent-switch not built on servers)
    activation.seedClaudeSettings = lib.mkForce (
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
}
