{
  config,
  configSource,
  lib,
  pkgs,
  rex,
  ...
}:
let
  cfg = config.dotfiles.rex;
  ghostty = config.programs.ghostty.settings;
  # Home Manager normalizes Ghostty settings to lists. Ghostty uses the last
  # value of a setting, and the first font family (the rest are fallbacks).
  setting = key: lib.last (lib.toList ghostty.${key});
  optionAsAlt = lib.last (lib.toList (ghostty.macos-option-as-alt or false));
  # The Rex app's look: Ghostty's colors, font and padding, with the sidebar
  # on the left. scripts/rex-app-defaults.py writes it into the app's defaults.
  appLook = pkgs.writeText "rex-app-look.json" (
    builtins.toJSON {
      name = "Dotfiles Monokai";
      colors = {
        background = setting "background";
        foreground = setting "foreground";
        cursor = setting "cursor-color";
        cursorText = setting "cursor-text";
        selectionBackground = setting "selection-background";
        selectionForeground = setting "selection-foreground";
      };
      # Ghostty's palette entries read N=#RRGGBB, in order.
      ansi = map (entry: lib.last (lib.splitString "=" entry)) (lib.toList ghostty.palette);
      # Each setting is a defaults key and { <defaults write type> = value; }.
      settings = {
        "Workspace.appearance".string = "dark";
        # Rex's default puts the tabs above the panes, with no sidebar.
        "Workspace.tabStyle".string = "vertical";
        "Workspace.sidebarPosition".string = "left";
        "Workspace.terminalFontName".string = lib.head (lib.toList ghostty.font-family);
        "Workspace.terminalFontPointSize".float = setting "font-size";
        "Workspace.terminalPaddingX".float = setting "window-padding-x";
        "Workspace.terminalPaddingY".float = setting "window-padding-y";
        "Workspace.terminalSynthesizesMissingStyles".bool = setting "font-synthetic-style";
        "Workspace.terminalOptionKeyBehavior".string = if optionAsAlt then "actsAsAlt" else "automatic";
      }
      # The app stores an unblinking cursor as a custom interval of 0.
      // lib.optionalAttrs (!setting "cursor-style-blink") {
        "Workspace.terminalCursorBlinkIntervalMilliseconds".int = 0;
        "Workspace.terminalCursorBlinkUsesCustomInterval".bool = false;
      };
    }
  );
in
{
  imports = [ rex.homeManagerModules.default ];

  options.dotfiles.rex = {
    enable = lib.mkEnableOption "the Rex CLI and the shared init.lua";
    server = lib.mkEnableOption "a personal Rex server that clients reach over SSH (Linux)";
  };

  config = lib.mkIf cfg.enable {
    programs.rex.enable = true;
    # The guard needs programs.ssh, and ~/.ssh/config is hand-owned. Without
    # it Rex terminals keep TERM=xterm-256color, which every host knows.
    programs.rex.sshGuard = false;
    services.rex.enable = cfg.server;

    # Mutable, so `rex config reload` applies an edit without a switch.
    xdg.configFile."rex/init.lua" = {
      source = configSource "rex/init.lua";
      # Replace a hand-made copy instead of failing activation.
      force = true;
    };

    # The app owns its settings, so this rewrites only the look on each
    # switch. A running app shows it after a restart.
    home.activation.rexAppLook = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD ${pkgs.python3}/bin/python3 -I ${../../../scripts/rex-app-defaults.py} ${appLook}
      ''
    );

    # Rex puts the running server's own rex first on PATH in its terminals.
    # The macOS profile above re-prepends the Nix profile, which would put this
    # pinned CLI ahead of the app's newer one, so restore Rex's choice.
    programs.zsh.profileExtra = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
      lib.mkAfter ''
        if [ -n "''${REX_BIN_DIR:-}" ]; then
          path=("$REX_BIN_DIR" $path)
        fi
      ''
    );
  };
}
