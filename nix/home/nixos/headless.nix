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
    # CLI-safe shared modules only (no ghostty/GUI, no packages.nix to avoid nodejs conflict with clawdbot)
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
    ../shared/mise.nix
  ];

  programs.home-manager.enable = true;

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    stateVersion = "24.05";

    packages = with pkgs; [
      # Terminfo
      ncurses
      ghostty.terminfo

      # Essential CLI tools
      jq
      yq-go
      fzf
      ripgrep
      fd
      bat
      eza
      just
      gh
      curl
      wget
      unzip
    ];

    sessionPath = [
      "${config.home.homeDirectory}/.cargo/bin"
      "${config.home.homeDirectory}/.npm-global/bin"
      "${config.home.homeDirectory}/.local/bin"
      "${config.home.homeDirectory}/go/bin"
      "${config.home.homeDirectory}/dotfiles/bin"
    ];

    activation.ensureDotfiles = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
      repo=${lib.escapeShellArg dotfiles}
      if [ ! -d "$repo/.git" ]; then
        ${pkgs.git}/bin/git clone --depth 1 https://github.com/thrawny/dotfiles.git "$repo"
      fi
    '';

    file = {
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
      ".claude/.keep".text = "";
    };
  };
}
