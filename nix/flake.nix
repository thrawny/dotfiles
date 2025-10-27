{
  description = "NixOS + Hyprland + Home Manager (monorepo) using out-of-store symlinks into this repo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nixos-hardware,
      zen-browser,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      mkHost =
        {
          system,
          modules,
        }:
        lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit zen-browser;
          };
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

        thrawny-desktop = mkHost {
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

      packages.x86_64-linux.desktop-iso =
        self.nixosConfigurations.desktop-iso.config.system.build.isoImage;
      packages.x86_64-linux.thrawny-desktop-iso =
        self.nixosConfigurations.desktop-iso.config.system.build.isoImage;

      homeConfigurations.thrawnym1 = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-darwin;
        modules = [ ./home/darwin/default.nix ];
        extraSpecialArgs = import ./hosts/thrawnym1/default.nix;
      };
    };
}
