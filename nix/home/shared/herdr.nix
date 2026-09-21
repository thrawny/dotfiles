{
  config,
  herdr,
  lib,
  pkgs,
  theme,
  zmx,
  ...
}:

let
  inherit (pkgs.stdenv.hostPlatform) system;
  hmLib = lib.hm;
  herdrPackage = herdr.packages.${system}.default;
  zmxPackage = zmx.packages.${system}.zmx-main;
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
      for plugin in "${pluginDir}"/*; do
        [ -d "$plugin" ] || continue
        $DRY_RUN_CMD ${herdrPackage}/bin/herdr plugin link \
          "$plugin" --enabled >/dev/null || \
          echo "herdr plugin link failed for $plugin; run it by hand once the server is up" >&2
      done
    fi
  '';

  # Modifier split, held across macOS and Linux: alt belongs to the window
  # manager, super belongs to applications, alt+super is the window manager
  # again. So Herdr lives on super, and anything touched often gets a super
  # binding next to its prefix one. super+c/v/x are copy/paste/cut, and
  # super+space, super+tab, super+q and super+shift+3/4/5 belong to the OS.
  #
  # Tabs and panes keep the familiar prefix-based bindings, except number keys
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
      # Numbered workspace switching has nowhere to live: super+shift+1..9 is
      # screenshots on both macOS and Hyprland. Cycling covers it instead, on
      # super+u/i to match the WM's own previous/next workspace keys.
      switch_workspace = "";
      next_workspace = "super+i";
      previous_workspace = "super+u";

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

      new_tab = [
        "prefix+c"
        "super+enter"
      ];
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
      # Closing keeps shift on the super variants: a bare super+w or super+x is
      # muscle memory from every other app and these kill a live agent.
      close_tab = [
        "prefix+shift+x"
        "super+shift+w"
      ];
      # ctrl+hjkl always reaches the terminal so Neovim splits and fzf keep
      # those keys. Two panes plus super+m (cycle_pane_next) covers the rest.
      focus_pane_left = "";
      focus_pane_down = "";
      focus_pane_up = "";
      focus_pane_right = "";
      # cycle_pane_next stays inside the focused tab, unlike last_pane, which is
      # a global back-and-forth that can land in another workspace. With two
      # panes, cycling is a toggle.
      cycle_pane_next = [
        "prefix+tab"
        "super+m"
      ];
      # Herdr has no last-workspace action, and landing in another workspace is
      # exactly what is wanted here. One level up from super+m, matching the
      # window manager's alt+m focus-last and alt+shift+m previous-workspace.
      last_pane = "super+shift+m";
      split_vertical = "prefix+v";
      split_horizontal = "prefix+minus";
      close_pane = [
        "prefix+x"
        "super+shift+x"
      ];

      # super+o goes to the next-agent plugin instead: a ranked queue beats
      # jumping to whichever pane happened to raise the last toast.
      open_notification_target = "";
      command = [
        {
          key = "super+o";
          type = "plugin_action";
          command = "thrawny.next-agent.focus";
          description = "Jump to the agent that needs you most";
        }
        {
          key = "super+p";
          type = "plugin_action";
          command = "thrawny.project-picker.open";
          description = "Pick a project";
        }
        {
          # A popup is session-modal, so this scratchpad is global rather than
          # per workspace. Herdr respawns the popup command on every open and
          # routes every key to it until it exits, so persistence has to come
          # from the command: zmx reattaches the same session, keeping the
          # shell, its scrollback, and anything still running. Detach with
          # ctrl+\, which also closes the popup.
          key = "super+s";
          type = "popup";
          command = "${zmxPackage}/bin/zmx attach scratch";
          width = "80%";
          height = "80%";
          description = "Scratchpad terminal";
        }
      ];
      reload_config = "prefix+shift+r";
    };

    ui = {
      tab_bar_position = "bottom";
      prompt_new_tab_name = false;
      # The focused pane gets an accent-colored frame. Shared dividers alone
      # cannot show focus, so each pane needs its own outer border.
      pane_borders = "auto";
      pane_outer_borders = true;
      pane_scrollbars = false;
      pane_gaps = true;
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
        active_row_bg = theme.applications.herdr.activeRowBg;
        selection_bg = theme.semantic.selection;
        surface0 = theme.semantic.surface;
        surface1 = theme.applications.herdr.surface;
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
