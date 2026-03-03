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
    #
    # To migrate an existing machine to this setup:
    #   1. Close Zen
    #   2. mv ~/.config/zen/<old-profile-dir> ~/.config/zen/default
    #   3. sed -i 's|<old-profile-dir>|default|g' ~/.config/zen/default/extensions.json ~/.config/zen/default/pkcs11.txt
    #   4. rm ~/.config/zen/default/addonStartup.json.lz4
    #   5. just switch && open Zen
    profiles.default = {
      isDefault = true;
      path = "default";
    };
  };
}
