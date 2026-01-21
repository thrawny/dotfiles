{
  lib,
  pkgs,
  dotfiles,
  ...
}:

let
  # Monokai Pro color palette
  colors = {
    bg = "#2d2a2e";
    fg = "#fcfcfa";
    yellow = "#ffd866";
    green = "#a9dc76";
    pink = "#ff6188";
    gray = "#5b595c";
    darkGray = "#403e41";
    dimGray = "#727072";
    lightGray = "#939293";
  };

  # Terminal settings
  terminalSettings = ''
    set -as terminal-overrides ',*:sitm=\E[3m'
    set -as terminal-features ",*:hyperlinks"
    set -g allow-passthrough on
  '';

  # Window navigation
  windowNavigation = ''
    # Window navigation with Ctrl+Shift+h/l (non-prefix)
    bind -n C-S-h previous-window
    bind -n C-S-l next-window

    # Alternative window navigation (prefix + h/l)
    bind h previous-window
    bind l next-window

    # Backup for nested sessions
    bind n next-window
    bind p previous-window

    # Rebind prefix + , to last-window (instead of rename-window)
    bind , last-window

    # Prefix + . switches to the last session
    bind . switch-client -l
  '';

  # Pane and window management
  paneManagement = ''
    # Split panes using | and - (more intuitive), preserve path
    bind | split-window -h -c "#{pane_current_path}"
    bind - split-window -v -c "#{pane_current_path}"
    bind '"' split-window -v -c "#{pane_current_path}"
    bind % split-window -h -c "#{pane_current_path}"

    # New window with current path (created after current window)
    bind c new-window -a -c "#{pane_current_path}"

    # Reorder windows - move current window left/right
    bind < swap-window -t -1 \; previous-window
    bind > swap-window -t +1 \; next-window

    # Kill pane/window without confirmation
    bind x kill-pane
    bind X kill-window
  '';

  # Session switching and scratch popups
  sessionSwitching = ''
    # Pass-through for nested tmux sessions
    bind C-n send-keys C-a n
    bind C-p send-keys C-a p

    # Persistent scratch terminal
    bind ` display-popup -E -w 80% -h 80% "tmux new-session -A -s scratch -c ~"
    bind '~' display-popup -E -w 80% -h 80% "tmux new-session -A -s scratch"

    # Two-stage session/window switcher (Ctrl+` on Mac, Ctrl+< on Linux)
    bind-key -n C-` display-popup -E -w 60% -h 60% "${dotfiles}/bin/tmux-fzf-switcher"
    bind-key -n 'C-<' display-popup -E -w 60% -h 60% "${dotfiles}/bin/tmux-fzf-switcher"
  '';

  # Copy mode bindings (tmux-yank handles clipboard, these add vim-style selection)
  copyModeBindings = ''
    bind-key -T copy-mode-vi v send-keys -X begin-selection
    bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle
  '';

  # Status bar styling
  statusBar = with colors; ''
    set -g status-position bottom
    set -g status-justify left
    set -g status-interval 10
    set -g status-style 'bg=${bg} fg=${fg}'

    # Left: Session name with prefix indicator
    set -g status-left-length 40
    set -g status-left ' #{?client_prefix,#[fg=${pink}]#[bold]  #S,#[fg=${green}]#[bold]  #S} #[fg=${gray}]|  '

    # Window status
    set -g window-status-separator '''
    set -g window-status-format '  #[fg=${dimGray}]#I:#[fg=${lightGray}]#W  '
    set -g window-status-current-format '#[bg=${darkGray}]  #[fg=${yellow},bold]#I:#[fg=${fg},bold]#W  #[bg=${bg}]'

    # Right: Empty with padding
    set -g status-right-length 1
    set -g status-right ' '

    # Pane borders
    set -g pane-border-style 'fg=${gray}'
    set -g pane-active-border-style 'fg=${yellow}'

    # Message style
    set -g message-style 'fg=${fg} bg=${darkGray} bold'
  '';

  # DevPod-specific settings
  devpodConfig = ''
    if-shell '[ -n "$DEVPOD" ]' 'set -g status off'
    if-shell '[ -n "$DEVPOD" ]' 'set -g detach-on-destroy off'
  '';

in
{
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    prefix = "C-a";
    keyMode = "vi";
    mouse = true;
    escapeTime = 0;
    historyLimit = 50000;
    baseIndex = 1;
    sensibleOnTop = false;

    plugins = with pkgs.tmuxPlugins; [
      yank
      {
        plugin = resurrect;
        extraConfig = "set -g @resurrect-capture-pane-contents 'on'";
      }
      {
        plugin = continuum;
        extraConfig = "set -g @continuum-restore 'on'";
      }
      vim-tmux-navigator
    ];

    extraConfig = lib.concatStringsSep "\n" [
      "# === Terminal Settings ==="
      terminalSettings

      "# === General ==="
      ''
        setw -g pane-base-index 1
        set-option -g renumber-windows on
        set-option -g automatic-rename on
        set-option -g automatic-rename-format '#{pane_current_command}'
        set-option -g allow-rename on

        # Send prefix for nested sessions
        bind a send-prefix
        bind C-a send-prefix
      ''

      "# === Window Navigation ==="
      windowNavigation

      "# === Pane Management ==="
      paneManagement

      "# === Session Switching ==="
      sessionSwitching

      "# === Copy Mode ==="
      copyModeBindings

      "# === Status Bar ==="
      statusBar

      "# === DevPod ==="
      devpodConfig

      "# === Misc ==="
      ''
        # Clear screen (C-l used by vim-tmux-navigator)
        bind C-l send-keys 'C-l'

        # Reload config
        bind R source-file ~/.config/tmux/tmux.conf \; display-message "Config reloaded..."
      ''
    ];
  };
}
