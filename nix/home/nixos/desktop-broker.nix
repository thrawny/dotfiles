{
  homeSource,
  lib,
  pkgs,
  ...
}@args:
let
  containerAssets = args.containerAssets or null;
  dotfiles = args.dotfiles or null;
  openUrl =
    if homeSource == "repo" then
      "${dotfiles}/bin/open-url"
    else
      "${containerAssets.bin}/open-url";

  # The sandbox can write the checkout. Never execute its mutable scripts on
  # the host in response to a broker request.
  broker = pkgs.writeText "desktop-broker.py" (builtins.readFile ../../../bin/desktop-broker);
  hostRouter = pkgs.writeShellScript "desktop-broker-open-url" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.jq
        pkgs.niri
        pkgs.hyprland
        pkgs.wl-clipboard
        pkgs.wtype
      ]
    }:/run/current-system/sw/bin
    ${builtins.readFile ../../../bin/open-url}
  '';
in
{
  systemd.user.sockets.desktop-broker = {
    Unit = {
      Description = "Restricted host desktop operations for sandboxes";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session-pre.target" ];
    };
    Socket = {
      ListenStream = "%t/desktop-broker/broker.sock";
      SocketMode = "0600";
      DirectoryMode = "0700";
      RemoveOnStop = true;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # One socket-activated process serializes focus/clipboard operations. It
  # stays alive after requests, including when the router starts a browser.
  systemd.user.services.desktop-broker = {
    Unit = {
      Description = "Restricted host desktop broker";
      Requires = [ "desktop-broker.socket" ];
      After = [
        "desktop-broker.socket"
        "graphical-session-pre.target"
      ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.python3}/bin/python3 -I ${broker} serve --opener ${hostRouter} --wl-paste ${pkgs.wl-clipboard}/bin/wl-paste";
      Restart = "on-failure";
      RestartSec = 1;
      UMask = "0077";
      WorkingDirectory = "%h";
      UnsetEnvironment = [
        "SANDBOX"
        "BASH_ENV"
        "ENV"
        "PYTHONPATH"
        "PYTHONHOME"
      ];
    };
  };

  xdg.desktopEntries.open-url = {
    name = "URL Router";
    comment = "Open URLs in the nearest Helium window, falling back to web workspace";
    exec = "${openUrl} %u";
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
      "x-scheme-handler/http" = [ "open-url.desktop" ];
      "x-scheme-handler/https" = [ "open-url.desktop" ];
      "text/html" = [ "open-url.desktop" ];
      "application/xhtml+xml" = [ "open-url.desktop" ];
    };
  };
}
