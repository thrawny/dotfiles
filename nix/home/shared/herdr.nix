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
  pluginRoot = "${config.home.homeDirectory}/dotfiles/config/herdr";
  pluginDir = "${pluginRoot}/plugins";
  extraPlugins = map (name: "${pluginRoot}/extra-plugins/${name}") config.dotfiles.herdr.extraPlugins;
in
{
  # Herdr has no per-plugin keybindings and no config drop-in directory, so
  # every custom binding has to reach this one generated config.toml. A list
  # option lets any module contribute: Home Manager concatenates the
  # definitions, so a host can add a binding for a plugin only it has without
  # the shared config naming it. Order does not matter, keys are distinct.
  options.dotfiles.herdr.commands = lib.mkOption {
    type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
    default = [ ];
    description = "[[keys.command]] entries for Herdr's config.toml.";
  };

  options.dotfiles.herdr.showAgentName = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Show the agent kind (claude, codex, ...) in sidebar agent rows.";
  };

  # Every plugin in config/herdr/plugins is linked on every machine. Ones that
  # only make sense on some hosts live in config/herdr/extra-plugins, and a
  # host names the ones it wants here.
  options.dotfiles.herdr.extraPlugins = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Directory names under config/herdr/extra-plugins to link on this host.";
  };

  config.home.packages = [ herdrPackage ];

  config.dotfiles.herdr.commands = [
    {
      # Pressing the prefix twice already sends a literal ctrl+a. This adds
      # tmux's send-prefix on prefix+a.
      key = "prefix+a";
      type = "shell";
      command = ''"$HERDR_BIN_PATH" pane send-keys "$HERDR_ACTIVE_PANE_ID" ctrl+a'';
      description = "Send ctrl+a to the pane";
    }
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
      key = "super+shift+p";
      type = "plugin_action";
      command = "thrawny.palette.open";
      description = "Command palette";
    }
  ];

  # Herdr keeps its plugin registry in ~/.config/herdr/plugins.json, which is
  # mutable state Nix does not manage, so a machine has no plugins until
  # something links them even though the manifests are in this repo. Linking
  # goes over the socket API and rewrites the entry for a plugin_root, so it
  # needs a running server and is safe to repeat.
  config.home.activation.linkHerdrPlugins = hmLib.dag.entryAfter [ "writeBoundary" ] ''
    if [ -S "$HOME/.config/herdr/herdr.sock" ]; then
      for plugin in "${pluginDir}"/* ${lib.escapeShellArgs extraPlugins}; do
        [ -d "$plugin" ] || continue
        $DRY_RUN_CMD ${herdrPackage}/bin/herdr plugin link \
          "$plugin" --enabled >/dev/null || \
          echo "herdr plugin link failed for $plugin; run it by hand once the server is up" >&2
      done
    fi
  '';

  # Keyboard policy and exceptions: docs/keyboard-rules.md at the repo root.
  # Frequent actions get direct super bindings alongside prefix bindings;
  # comments below explain Herdr-specific choices.
  config.xdg.configFile."herdr/config.toml".source =
    (pkgs.formats.toml { }).generate "herdr-config.toml"
      {
        onboarding = false;

        terminal = {
          shell_mode = "auto";
          new_cwd = "follow";
        };

        keys = {
          prefix = "ctrl+a";

          # Number keys select agents rather than tabs or workspaces.
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
          # Use cycling instead of shifted numbers, which overlap screenshot keys.
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
            "super+shift+enter"
          ];
          previous_tab = [
            "super+h"
            "ctrl+shift+h"
            "prefix+h"
            "prefix+p"
          ];
          next_tab = [
            "super+l"
            "ctrl+shift+l"
            "prefix+l"
            "prefix+n"
          ];
          move_tab_previous = "prefix+shift+comma";
          move_tab_next = "prefix+shift+period";
          close_tab = [
            "prefix+shift+x"
            "super+shift+w"
          ];
          # Disable directional pane shortcuts to preserve Ctrl+H/J/K/L for
          # Neovim and fzf. Use cycle_pane_next for Herdr panes instead.
          focus_pane_left = "";
          focus_pane_down = "";
          focus_pane_up = "";
          focus_pane_right = "";
          # Cycling stays within the tab; with two panes it acts as a toggle.
          cycle_pane_next = [
            "prefix+tab"
            "super+m"
          ];
          # Herdr has no last-workspace action. last_pane provides back-and-forth
          # across tabs and workspaces, unlike cycle_pane_next.
          last_pane = "super+shift+m";
          # Splitting beats a new tab for frequency, so it gets the unshifted key.
          split_vertical = [
            "prefix+v"
            "super+enter"
          ];
          split_horizontal = "prefix+minus";
          close_pane = [
            "prefix+x"
            "super+w"
          ];

          # super+o uses the next-agent plugin's priority order rather than
          # the most recent notification target.
          open_notification_target = "";
          command = config.dotfiles.herdr.commands;
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
              (
                [
                  {
                    token = "state_icon";
                    dim = false;
                  }
                  # Colors come from the palette slots remapped in theme.custom.
                  # Bold marks the states that wait on you.
                  {
                    token = "state_text";
                    dim = false;
                    rules = [
                      {
                        equals = "blocked";
                        bold = true;
                      }
                      {
                        equals = "done";
                        bold = true;
                      }
                    ];
                  }
                ]
                ++ lib.optional config.dotfiles.herdr.showAgentName {
                  token = "agent";
                  fg = theme.semantic.accentAlt;
                  dim = false;
                }
              )
              # Reported by bin/herdr-decorator. Values expire if it stops, and
              # the row disappears when a pane has no PR and no Jira key.
              [
                # The icon's shape is the PR's state and the mark after the
                # number is checks and review; see PR_ICONS in the decorator.
                # Waiting on review or checks stays white. Yellow means it needs
                # you, green means approved, purple is GitHub's merged color.
                {
                  token = "$pr";
                  fg = theme.semantic.foreground;
                  dim = false;
                  rules = [
                    {
                      starts_with = "";
                      fg = theme.semantic.accentAlt;
                    }
                    {
                      starts_with = "";
                      fg = theme.semantic.dim;
                    }
                    {
                      starts_with = "";
                      fg = theme.semantic.dim;
                    }
                    {
                      contains = "";
                      fg = theme.syntax.function;
                      bold = true;
                    }
                    {
                      contains = "±";
                      fg = theme.syntax.function;
                      bold = true;
                    }
                    {
                      contains = "";
                      fg = theme.semantic.success;
                    }
                  ];
                }
                {
                  token = "$jira";
                  fg = theme.semantic.accent;
                  dim = false;
                }
              ]
              [
                # Reported by bin/herdr-decorator: the workspace name, or the
                # checkout the agent moved to, marked with an arrow. Blank if
                # the decorator stops.
                {
                  token = "$where";
                  fg = theme.semantic.muted;
                  dim = false;
                  rules = [
                    {
                      starts_with = "→";
                      fg = theme.semantic.accentAlt;
                    }
                  ];
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
            # Red-green color-blind safe: color means "look here", on a
            # blue/yellow axis only. Herdr colors agent states from these
            # slots (idle=green, working=yellow, blocked=red, done=teal), so
            # the slot names no longer match their colors. Idle goes gray,
            # working blue, blocked yellow and done green. Online endpoints and
            # installed integrations also use green, so they go gray too.
            green = theme.semantic.muted;
            yellow = theme.syntax.type;
            red = theme.syntax.function;
            blue = theme.syntax.type;
            teal = theme.semantic.success;
            peach = theme.semantic.warning;
          };
        };

        advanced.scrollback_limit_bytes = 50000000;
      };
}
