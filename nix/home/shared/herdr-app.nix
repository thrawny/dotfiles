{
  config,
  configPath,
  configSource,
  lib,
  pkgs,
  theme,
  thrawny-pkgs,
  ...
}:
let
  cfg = config.dotfiles.herdrApp;
  # Terminals use Ghostty's colors, so both apps look the same.
  ghostty = theme.applications.ghostty;
  terminalTheme = pkgs.writeText "herdr-app-thrawny-theme.json" (
    builtins.toJSON {
      inherit (ghostty) background foreground cursor;
      selection = ghostty.selectionBackground;
      ansi = ghostty.palette;
      # Red-green colour-blind safe, as in the TUI (herdr.nix): colour means
      # "look here", on a blue/yellow axis only.
      colors = {
        idle = theme.semantic.muted;
        working = theme.syntax.type;
        blocked = theme.syntax.function;
        done = theme.semantic.success;
      };
    }
  );
  # Terminals use Ghostty's font too. Ghostty sizes fonts in points, which
  # are 4/3 of a pixel on Linux and one pixel on macOS. Herdr takes pixels.
  ghosttySettings = config.programs.ghostty.settings;
  # Home Manager's key-value format normalizes settings to lists. Ghostty
  # uses the last size and the first font family (the rest are fallbacks).
  fontFamily = lib.head (lib.toList ghosttySettings.font-family);
  fontSizePoints = lib.last (lib.toList ghosttySettings.font-size);
  # On Linux, Ghostty's points become px at 4/3; Herdr draws the same px
  # slightly smaller than Ghostty does, so it gets 5% more.
  fontSize =
    if pkgs.stdenv.hostPlatform.isDarwin then fontSizePoints else fontSizePoints * 4.0 / 3 * 1.05;
  mods = [
    "thrawny-agents"
    "thrawny-pane"
    "thrawny-picker"
    "thrawny-prefix"
    "thrawny-projects"
    "thrawny-tabs"
  ];
in
{
  options.dotfiles.herdrApp.enable = lib.mkEnableOption "personal Herdr desktop bindings and mods";

  config = lib.mkIf cfg.enable {
    # macOS keeps its native app install; Linux packages come from nix-pkgs.
    home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      thrawny-pkgs.packages.${pkgs.stdenv.hostPlatform.system}.herdr-app
      thrawny-pkgs.packages.${pkgs.stdenv.hostPlatform.system}.herdr-core
    ];

    xdg.configFile = lib.genAttrs (map (name: "herdr-app/mods/${name}") mods) (name: {
      source = configSource name;
    });

    # Keys and layouts are writable because the app edits them atomically.
    # Activation reapplies our baseline; application-owned state stays separate.
    home.activation.configureHerdrApp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -Dm644 \
        ${lib.escapeShellArg (configPath "herdr-app/keys.json")} \
        "$HOME/.config/herdr-app/keys.json"
      layout=$(${pkgs.coreutils}/bin/mktemp)
      ${pkgs.jq}/bin/jq \
        --arg font ${lib.escapeShellArg fontFamily} \
        --argjson size ${toString fontSize} \
        '.font = $font | .font_size = $size' \
        ${lib.escapeShellArg (configPath "herdr-app/layouts/thrawny.json")} >"$layout"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -Dm644 "$layout" \
        "$HOME/.config/herdr-app/layouts/thrawny.json"
      ${pkgs.coreutils}/bin/rm -f "$layout"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -Dm644 ${terminalTheme} \
        "$HOME/.config/herdr-app/themes/thrawny.json"
      if [ ! -e "$HOME/.config/herdr-app/shared.json" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m644 \
          ${pkgs.writeText "herdr-app-initial-state.json" (builtins.toJSON { layout = "thrawny"; })} \
          "$HOME/.config/herdr-app/shared.json"
      fi
    '';
  };
}
