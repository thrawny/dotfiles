{ ... }:
{
  imports = [
    ./system.nix
  ];

  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;

  nix = {
    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 3d";
    };
    optimise.automatic = true;
    settings = {
      keep-derivations = false;
      keep-outputs = false;
    };
  };
}
