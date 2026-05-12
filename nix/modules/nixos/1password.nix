{ config, ... }:
{
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ config.dotfiles.username ];
  };

  # Allow Nix-installed browsers to use the 1Password browser extension.
  # Helium is installed as a system package in desktop.nix from the
  # helium-browser flake; include both launcher and wrapped binary names.
  environment.etc."1password/custom_allowed_browsers" = {
    text = ''
      zen
      .zen-wrapped
      helium
      .helium-wrapped
      google-chrome
    '';
    mode = "0755";
  };
}
