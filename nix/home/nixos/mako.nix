_:
{
  services.mako = {
    enable = true;
    settings = {
      # Molokai colors with full opacity
      background-color = "#1c1c1cff";
      text-color = "#f0f0f0ff";
      border-color = "#3a3a3aff";
      progress-color = "#66d9efff";

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
