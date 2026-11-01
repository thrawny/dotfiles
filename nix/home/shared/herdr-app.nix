{
  config,
  configPath,
  configSource,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.herdrApp;
  mods = [
    "thrawny-agents"
    "thrawny-prefix"
    "thrawny-projects"
    "thrawny-tabs"
  ];
in
{
  options.dotfiles.herdrApp.enable = lib.mkEnableOption "personal Herdr desktop bindings and mods";

  config = lib.mkIf cfg.enable {
    xdg.configFile = lib.genAttrs (map (name: "herdr-app/mods/${name}") mods) (name: {
      source = configSource name;
    });

    # Keys and layouts are writable because the app edits them atomically.
    # Activation reapplies our baseline; application-owned state stays separate.
    home.activation.configureHerdrApp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -Dm644 \
        ${lib.escapeShellArg (configPath "herdr-app/keys.json")} \
        "$HOME/.config/herdr-app/keys.json"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -Dm644 \
        ${lib.escapeShellArg (configPath "herdr-app/layouts/thrawny.json")} \
        "$HOME/.config/herdr-app/layouts/thrawny.json"
      if [ ! -e "$HOME/.config/herdr-app/shared.json" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m644 \
          ${pkgs.writeText "herdr-app-initial-state.json" (builtins.toJSON { layout = "thrawny"; })} \
          "$HOME/.config/herdr-app/shared.json"
      fi
    '';
  };
}
