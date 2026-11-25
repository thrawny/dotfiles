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
  # Ghostty's own theme keys, so Rex's import gets exactly Ghostty's colors.
  themeKeys = [
    "background"
    "foreground"
    "cursor-color"
    "cursor-text"
    "selection-background"
    "selection-foreground"
  ];
  ghosttyTheme = lib.concatStringsSep "\n" (
    map (key: "${key} = ${setting key}") themeKeys
    ++ map (entry: "palette = ${entry}") (lib.toList ghostty.palette)
  );
  themeName = "Dotfiles Monokai";
  # What init.lua's Match Ghostty Look action applies in the Rex app.
  ghosttyLook = {
    theme = "${config.xdg.configHome}/rex/themes/${themeName}";
    font = lib.head (lib.toList ghostty.font-family);
    size = setting "font-size";
    padding_x = setting "window-padding-x";
    padding_y = setting "window-padding-y";
    option_as_alt = lib.last (lib.toList (ghostty.macos-option-as-alt or false));
    cursor_blink = setting "cursor-style-blink";
    synthesize = setting "font-synthetic-style";
  };
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

    xdg.configFile = {
      # Mutable, so `rex config reload` applies an edit without a switch.
      "rex/init.lua" = {
        source = configSource "rex/init.lua";
        # Replace a hand-made copy instead of failing activation.
        force = true;
      };
    }
    # Only the Mac runs the app that imports these.
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      "rex/themes/${themeName}".text = ghosttyTheme + "\n";
      "rex/ghostty-look.json".text = builtins.toJSON ghosttyLook;
    };

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
