{ config, dotfiles, lib, ... }:
let
  hmLib = lib.hm;
in
{
  home.file.".tmux.conf".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/tmux/tmux.conf";

  # Install TPM (Tmux Plugin Manager)
  home.activation.installTpm = hmLib.dag.entryAfter [ "writeBoundary" ] ''
    tpm_dir="$HOME/.tmux/plugins/tpm"
    if [ ! -d "$tpm_dir" ]; then
      echo "Installing TPM (Tmux Plugin Manager)..."
      $DRY_RUN_CMD mkdir -p "$HOME/.tmux/plugins"
      if [ -z "$DRY_RUN" ]; then
        git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
      fi
    fi
  '';

  # Install tmux plugins (via TPM)
  home.activation.installTmuxPlugins = hmLib.dag.entryAfter [ "installTpm" ] ''
    if [ -f "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]; then
      if [ ! -d "$HOME/.tmux/plugins/tmux-yank" ]; then
        echo "Installing tmux plugins..."
        if [ -z "$DRY_RUN" ]; then
          "$HOME/.tmux/plugins/tpm/bin/install_plugins"
        fi
      fi
    fi
  '';
}
