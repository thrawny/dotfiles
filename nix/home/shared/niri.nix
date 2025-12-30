# Niri window manager configuration
# Supports both base config and DMS (DankMaterialShell) overlay
{
  config,
  lib,
  dotfiles,
  ...
}:
let
  cfg = config.custom.niri;
  configFile = if cfg.enableDms then "dms/config.kdl" else "base.kdl";
in
{
  options.custom.niri = {
    enable = lib.mkEnableOption "niri window manager configuration";

    enableDms = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable DankMaterialShell integration.
        When true, uses the DMS wrapper config with panel, launcher, etc.
        When false, uses the base config with fuzzel/swaylock.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile = {
      "niri/config.kdl".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/niri/${configFile}";
      "niri/base.kdl".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/niri/base.kdl";
      "niri/binds-base.kdl".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/niri/binds-base.kdl";
      "niri/dms".source =
        config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/niri/dms";
    };

    # Create empty colors.kdl if missing (DMS regenerates it from GUI)
    home.activation.ensureDmsColors = lib.mkIf cfg.enableDms (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        colorsFile="${dotfiles}/config/niri/dms/colors.kdl"
        if [ ! -f "$colorsFile" ]; then
          $DRY_RUN_CMD touch "$colorsFile"
        fi
      ''
    );
  };
}
