{
  config,
  herdr,
  lib,
  pkgs,
  theme,
  ...
}:

let
  inherit (pkgs.stdenv.hostPlatform) system;
  hmLib = lib.hm;
  herdrPackage = herdr.packages.${system}.default;
  herdrNav = "${config.home.homeDirectory}/dotfiles/bin/herdr-nav";
  pluginDir = "${config.home.homeDirectory}/dotfiles/config/herdr/plugins";
in
{
  home.packages = [ herdrPackage ];

  # Herdr keeps its plugin registry in ~/.config/herdr/plugins.json, which is
  # mutable state Nix does not manage, so a machine has no plugins until
  # something links them even though the manifests are in this repo. Linking
  # goes over the socket API and rewrites the entry for a plugin_root, so it
  # needs a running server and is safe to repeat.
  home.activation.linkHerdrPlugins = hmLib.dag.entryAfter [ "writeBoundary" ] ''
    if [ -S "$HOME/.config/herdr/herdr.sock" ]; then
      $DRY_RUN_CMD ${herdrPackage}/bin/herdr plugin link \
        "${pluginDir}/project-picker" --enabled >/dev/null || \
        echo "herdr plugin link failed; run it by hand once the server is up" >&2
    fi
  '';

  # Tabs and panes mirror tmux where concepts overlap, except number keys
  # select agents. Workspace navigation uses j/k as well as the arrow keys.
  xdg.configFile."herdr/config.toml".source = (pkgs.formats.toml { }).generate "herdr-config.toml" {
    onboarding = false;

    terminal = {
      shell_mode = "auto";
      new_cwd = "follow";
    };

    keys = {
      prefix = "ctrl+a";

      focus_agent = [
        "prefix+1..9"
        "super+1..9"
      ];
      next_agent = [
        "prefix+j"
        "super+j"
      ];
      previous_agent = [
        "prefix+k"
        "super+k"
      ];
      switch_tab = "";
      next_workspace = "super+shift+j";
      previous_workspace = "super+shift+k";

      navigate_workspace_down = [
        "j"
        "down"
      ];
      navigate_workspace_up = [
        "k"
        "up"
      ];
      # In workspace navigation mode, reserve j/k for workspace selection.
      navigate_pane_down = "";
      navigate_pane_up = "";

      new_tab = "prefix+c";
      previous_tab = [
        "ctrl+shift+h"
        "prefix+h"
        "prefix+p"
      ];
      next_tab = [
        "ctrl+shift+l"
        "prefix+l"
        "prefix+n"
      ];
      move_tab_previous = "prefix+shift+comma";
      move_tab_next = "prefix+shift+period";
      close_tab = "prefix+shift+x";
      # ctrl+hjkl goes through herdr-nav instead of focus_pane_*, so Vim and fzf
      # keep those keys when they are running in the focused pane. Herdr has no
      # conditional keybindings, so the process check lives in the script.
      focus_pane_left = "";
      focus_pane_down = "";
      focus_pane_up = "";
      focus_pane_right = "";
      split_vertical = "prefix+v";
      split_horizontal = "prefix+minus";
      close_pane = "prefix+x";

      open_notification_target = [
        "prefix+o"
        "super+o"
      ];
      command = [
        {
          key = "super+p";
          type = "plugin_action";
          command = "thrawny.project-picker.open";
          description = "Pick a project";
        }
        {
          key = "ctrl+h";
          type = "shell";
          command = "${herdrNav} left";
          description = "Focus pane left, or send ctrl+h to Vim or fzf";
        }
        {
          key = "ctrl+j";
          type = "shell";
          command = "${herdrNav} down";
          description = "Focus pane down, or send ctrl+j to Vim or fzf";
        }
        {
          key = "ctrl+k";
          type = "shell";
          command = "${herdrNav} up";
          description = "Focus pane up, or send ctrl+k to Vim or fzf";
        }
        {
          key = "ctrl+l";
          type = "shell";
          command = "${herdrNav} right";
          description = "Focus pane right, or send ctrl+l to Vim or fzf";
        }
      ];
      reload_config = "prefix+shift+r";
    };

    ui = {
      tab_bar_position = "bottom";
      prompt_new_tab_name = false;
      pane_outer_borders = false;
      pane_scrollbars = false;
      pane_gaps = false;
      sidebar_start_collapsed = false;
      sidebar_width = 26;
      sidebar_collapsed_mode = "compact";
      status_indicators = "symbols";
      sidebar.agents = {
        row_gap = 1;
        rows = [
          [
            {
              token = "terminal_title_stripped";
              fg = theme.semantic.foreground;
              bold = true;
              dim = false;
            }
          ]
          [
            {
              token = "state_icon";
              dim = false;
            }
            {
              token = "state_text";
              dim = false;
            }
            {
              token = "agent";
              fg = theme.semantic.accentAlt;
              dim = false;
            }
          ]
          [
            {
              token = "workspace";
              fg = theme.semantic.muted;
              dim = false;
            }
            {
              token = "machine";
              fg = theme.semantic.muted;
              dim = false;
            }
          ]
        ];
      };
    };

    theme = {
      name = "terminal";
      custom = {
        accent = theme.semantic.accent;
        panel_bg = theme.semantic.surface;
        sidebar_bg = theme.semantic.background;
        active_row_bg = theme.applications.tmux.darkGray;
        selection_bg = theme.semantic.selection;
        surface0 = theme.semantic.surface;
        surface1 = theme.applications.tmux.bg;
        surface_dim = theme.semantic.background;
        overlay0 = theme.semantic.border;
        overlay1 = theme.semantic.muted;
        text = theme.semantic.foreground;
        subtext0 = theme.semantic.muted;
        mauve = theme.semantic.accentAlt;
        green = theme.semantic.success;
        yellow = theme.syntax.function;
        red = theme.semantic.error;
        blue = theme.syntax.type;
        teal = theme.syntax.type;
        peach = theme.semantic.warning;
      };
    };

    advanced.scrollback_limit_bytes = 50000000;
  };
}
