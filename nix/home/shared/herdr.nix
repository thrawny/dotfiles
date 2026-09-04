{
  herdr,
  pkgs,
  theme,
  ...
}:

let
  inherit (pkgs.stdenv.hostPlatform) system;
in
{
  home.packages = [ herdr.packages.${system}.default ];

  # Herdr tabs and panes mirror the tmux window/pane workflow where the
  # concepts overlap. Herdr-only workspace and agent controls keep defaults.
  xdg.configFile."herdr/config.toml".source = (pkgs.formats.toml { }).generate "herdr-config.toml" {
    onboarding = false;

    terminal = {
      shell_mode = "auto";
      new_cwd = "follow";
    };

    keys = {
      prefix = "ctrl+a";

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

      focus_pane_left = "ctrl+h";
      focus_pane_down = "ctrl+j";
      focus_pane_up = "ctrl+k";
      focus_pane_right = "ctrl+l";
      split_vertical = "prefix+v";
      split_horizontal = "prefix+minus";
      close_pane = "prefix+x";

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
