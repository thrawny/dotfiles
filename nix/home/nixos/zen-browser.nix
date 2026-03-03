{ zen-browser, ... }:
{
  imports = [ zen-browser.homeModules.default ];

  programs.zen-browser = {
    enable = true;
    suppressXdgMigrationWarning = true;

    # Declarative profile prevents the profile reset issue on Nix rebuilds.
    # The wrapper sets MOZ_LEGACY_PROFILES=1, and Home Manager manages
    # profiles.ini so the default profile is always correctly resolved
    # regardless of store path changes.
    # See: https://github.com/NixOS/nixpkgs/issues/58923
    profiles.default = {
      isDefault = true;
      path = "default";
    };
  };
}
