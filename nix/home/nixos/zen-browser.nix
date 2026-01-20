{ zen-browser, ... }:
{
  imports = [ zen-browser.homeModules.default ];

  programs.zen-browser = {
    enable = true;
  };

  # Fix profile reset on Nix rebuilds
  # Firefox/Zen generates Install IDs from the binary path hash. When Nix updates
  # the package, the store path changes, creating a new Install ID and causing
  # Zen to start with a fresh profile.
  # MOZ_LEGACY_PROFILES=1 should fix this but doesn't work reliably with desktop launchers.
  # The reliable fix is to pass -p "profile-name" directly.
  # See: https://github.com/NixOS/nixpkgs/issues/58923
  # See: https://github.com/0xc000022070/zen-browser-flake/issues/179
  xdg.desktopEntries.zen-beta = {
    name = "Zen Browser (Beta)";
    genericName = "Web Browser";
    exec = ''zen-beta --name zen-beta -p "Default Profile" %U'';
    icon = "zen-browser";
    terminal = false;
    type = "Application";
    categories = [
      "Network"
      "WebBrowser"
    ];
    mimeType = [
      "text/html"
      "text/xml"
      "application/xhtml+xml"
      "application/vnd.mozilla.xul+xml"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ];
    startupNotify = true;
    settings = {
      StartupWMClass = "zen-beta";
      Version = "1.5";
    };
    actions = {
      new-window = {
        name = "New Window";
        exec = ''zen-beta --new-window -p "Default Profile" %U'';
      };
      new-private-window = {
        name = "New Private Window";
        exec = ''zen-beta --private-window -p "Default Profile" %U'';
      };
      profile-manager-window = {
        name = "Profile Manager";
        exec = "zen-beta --ProfileManager";
      };
    };
  };
}
