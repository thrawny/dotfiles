{ lib, ... }:
let
  warning = ''Populate nix/hosts/thinkpad/hardware-configuration.nix with the output of `nixos-generate-config` from the laptop.'';
in
{
  assertions = [
    {
      assertion = false;
      message = warning;
    }
  ];
}
