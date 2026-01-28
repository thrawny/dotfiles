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
    ../shared/mise.nix
  ];

  programs.home-manager.enable = true;

  home = {
    inherit username;
    homeDirectory = "/home/${username}";

    packages = with pkgs; [
      # Terminfo for SSH compatibility
      ncurses
      ghostty.terminfo
    ];

    activation.ensureDotfiles = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
      repo=${lib.escapeShellArg dotfiles}
      if [ ! -d "$repo/.git" ]; then
        ${pkgs.git}/bin/git clone --depth 1 https://github.com/thrawny/dotfiles.git "$repo"
      fi
    '';
  };
}
