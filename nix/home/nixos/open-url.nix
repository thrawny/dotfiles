{
  homeSource,
  ...
}@args:
let
  containerAssets = args.containerAssets or null;
  dotfiles = args.dotfiles or null;
  niriOpenUrl =
    if homeSource == "repo" then
      "${dotfiles}/bin/niri-open-url"
    else
      "${containerAssets.bin}/niri-open-url";
in
{
  xdg.desktopEntries.niri-open-url = {
    name = "Niri URL Router";
    comment = "Open URLs in the nearest Zen or Helium window";
    exec = "${niriOpenUrl} %u";
    terminal = false;
    type = "Application";
    mimeType = [
      "x-scheme-handler/http"
      "x-scheme-handler/https"
      "text/html"
      "application/xhtml+xml"
    ];
    settings.NoDisplay = "true";
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = [ "niri-open-url.desktop" ];
      "x-scheme-handler/https" = [ "niri-open-url.desktop" ];
      "text/html" = [ "niri-open-url.desktop" ];
      "application/xhtml+xml" = [ "niri-open-url.desktop" ];
    };
  };
}
