{
  description = "NixOS + Hyprland + Home Manager (monorepo) using out-of-store symlinks into this repo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nixos-hardware,
      ...
    }:
    let
      lib = nixpkgs.lib;
      mkHost =
        { system, modules }:
        lib.nixosSystem {
          inherit system;
          modules = [
            home-manager.nixosModules.home-manager
          ]
          ++ modules;
        };
    in
    {
      nixosConfigurations = {
        tester = mkHost {
          system = "x86_64-linux";
          modules = [ ./hosts/tester/default.nix ];
        };

        thinkpad = mkHost {
          system = "x86_64-linux";
          modules = [
            nixos-hardware.nixosModules.lenovo-thinkpad-t14
            ./hosts/thinkpad/default.nix
          ];
        };

        desktop = mkHost {
          system = "x86_64-linux";
          modules = [
            nixos-hardware.nixosModules.common-cpu-amd
            ./hosts/desktop/default.nix
          ];
        };

        desktop-iso = mkHost {
          system = "x86_64-linux";
          modules = [
            ./hosts/desktop-iso/default.nix
          ];
        };
      };

      packages.x86_64-linux.desktop-iso = self.nixosConfigurations.desktop-iso.config.system.build.isoImage;
    };
}
