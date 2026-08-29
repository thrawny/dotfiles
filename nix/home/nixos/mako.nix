{ theme, ... }:
let
  app = theme.applications.mako;
in
{
  services.mako = {
    enable = true;
    settings = {
      # Molokai colors with full opacity
      background-color = "${app.background}ff";
      text-color = "${app.text}ff";
      border-color = "${app.border}ff";
      progress-color = "${app.progress}ff";

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
