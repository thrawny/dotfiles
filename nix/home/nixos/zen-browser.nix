{ zen-browser, lib, ... }:
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
      keyboardShortcuts =
        let
          mkWorkspaceSwitch = n: {
            id = "zen-workspace-switch-${toString n}";
            key = toString n;
            modifiers.accel = true;
          };
          mkTabSwitch = n: id: {
            inherit id;
            key = toString n;
            modifiers.meta = true;
          };
        in
        # Ctrl+1-9: switch workspaces
        (map mkWorkspaceSwitch (lib.range 1 9))
        # Super+1-8: switch tabs, Super+9: last tab
        ++ (lib.imap1 (i: _: mkTabSwitch i "key_selectTab${toString i}") (lib.range 1 8))
        ++ [
          (mkTabSwitch 9 "key_selectLastTab")
        ]
        # Super+Left/Right: browser back/forward (Alt is reserved for Niri)
        ++ [
          {
            id = "goBackKb";
            keycode = "VK_LEFT";
            modifiers.meta = true;
          }
          {
            id = "goForwardKb";
            keycode = "VK_RIGHT";
            modifiers.meta = true;
          }
        ];
    };
  };
}
