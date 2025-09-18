{ lib, theme, ... }:
let
  palette = theme.palette;
  withAlpha = color: let base = lib.strings.removePrefix "#" color; in "#${base}ff";
in
{
  services.mako = {
    enable = true;
    settings = {
      background-color = withAlpha palette.background;
      text-color = withAlpha palette.text;
      border-color = withAlpha palette.border;
      progress-color = withAlpha palette.accent;

      width = 420;
      height = 110;
      padding = "10";
      margin = "10";
      border-size = 2;
      border-radius = 6;

      anchor = "top-right";
      layer = "overlay";

      default-timeout = 5000;
      ignore-timeout = false;
      max-visible = 5;
      sort = "-time";
      group-by = "app-name";

      actions = true;
      format = "<b>%s</b>\\n%b";
      markup = true;
    };
  };
}
