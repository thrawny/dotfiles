{
  description = "NixOS + Home Manager (monorepo) using out-of-store symlinks into this repo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Pinned for xwayland 24.1.0 (newer versions crash Steam under xwayland-satellite)
    nixpkgs-xwayland.url = "github:NixOS/nixpkgs/b60793b86201040d9dee019a05089a9150d08b5b";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-index-database.url = "github:Mic92/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nur.url = "github:nix-community/NUR";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";
    helium-browser.url = "github:schembriaiden/helium-browser-nix-flake";
    helium-browser.inputs.nixpkgs.follows = "nixpkgs";
    elephant.url = "github:abenz1267/elephant";
    walker.url = "github:abenz1267/walker";
    walker.inputs.elephant.follows = "elephant";
    niri-flake.url = "github:sodiboo/niri-flake";
    niri-flake.inputs.niri-stable.url = "github:YaLTeR/niri/v25.11";
    xremap-flake.url = "github:xremap/nix-flake";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    # Pin to PR #771: fix deprecated systemd.sleep.extraConfig for NixOS 26.05
    srvos.url = "github:nix-community/srvos/752772adba542cab1162ad271f0b3d69adc59349";
    srvos.inputs.nixpkgs.follows = "nixpkgs";
    claude-code-nix.url = "github:sadjow/claude-code-nix";
    llm-agents.url = "github:numtide/llm-agents.nix";
    zmx.url = "github:thrawny/zmx-flake";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nix-index-database,
      nixos-hardware,
      nur,
      zen-browser,
      helium-browser,
      walker,
      niri-flake,
      xremap-flake,
      nixpkgs-xwayland,
      disko,
      srvos,
      claude-code-nix,
      llm-agents,
      zmx,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      flakeArgs = {
        inherit
          claude-code-nix
          llm-agents
          nix-index-database
          zmx
          ;
      };
      storeHomeAssets = {
        config = builtins.path {
          path = ../config;
          name = "dotfiles-config";
        };
        skills = builtins.path {
          path = ../skills;
          name = "dotfiles-skills";
        };
        bin = builtins.path {
          path = ../bin;
          name = "dotfiles-bin";
        };
      };

      mkHost =
        {
          system,
          modules,
        }:
        let
          nurPkgs = import nur {
            nurpkgs = nixpkgs.legacyPackages.${system};
            pkgs = nixpkgs.legacyPackages.${system};
          };
        in
        lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit
              self
              zen-browser
              walker
              nurPkgs
              xremap-flake
              nixpkgs-xwayland
              helium-browser
              ;
          };
          modules = [
            srvos.nixosModules.desktop
            srvos.nixosModules.mixins-trusted-nix-caches
            home-manager.nixosModules.home-manager
            niri-flake.nixosModules.niri # cached niri package + system setup
            zmx.nixosModules.cache
            {
              nixpkgs.overlays = [
                niri-flake.overlays.niri
                # Pin spotify to 1.2.74 (close button broken with minimize-to-tray since 1.2.79)
                (_: prev: {
                  spotify = prev.spotify.overrideAttrs (_: {
                    version = "1.2.74.477.g3be53afe";
                    rev = "89";
                    src = prev.fetchurl {
                      name = "spotify-1.2.74.477.g3be53afe-89.snap";
                      url = "https://api.snapcraft.io/api/v1/snaps/download/pOBIoZ2LrCB3rDohMxoYGnbN14EHOgD7_89.snap";
                      hash = "sha512-mn1w/Ylt9weFgV67tB435CoF2/4V+F6gu1LUXY07J6m5nxi1PCewHNFm8/11qBRO/i7mpMwhcRXaiv0HkFAjYA==";
                    };
                  });
                })
              ];
            }
            {
              home-manager.extraSpecialArgs = flakeArgs // {
                containerAssets = storeHomeAssets;
              };
            }
          ]
          ++ modules;
        };

      # Headless hosts (servers) - no desktop/Wayland modules
      mkHeadlessHost =
        {
          system,
          modules,
        }:
        let
          nurPkgs = import nur {
            nurpkgs = nixpkgs.legacyPackages.${system};
            pkgs = nixpkgs.legacyPackages.${system};
          };
        in
        lib.nixosSystem {
          inherit system;
          specialArgs = {
            # system.nix requires these even if headless HM doesn't use them
            inherit
              self
              zen-browser
              walker
              nurPkgs
              xremap-flake
              ;
          };
          modules = [
            srvos.nixosModules.server
            srvos.nixosModules.mixins-trusted-nix-caches
            home-manager.nixosModules.home-manager
            disko.nixosModules.disko
            zmx.nixosModules.cache
            {
              home-manager.extraSpecialArgs = flakeArgs // {
                containerAssets = storeHomeAssets;
              };
            }

          ]
          ++ modules;
        };

      mkHomeConfiguration =
        {
          pkgs,
          modules,
          extraSpecialArgs ? { },
        }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs modules;
          extraSpecialArgs = extraSpecialArgs // flakeArgs;
        };

    in
    {
      nixosConfigurations = {
        thinkpad = mkHost {
          system = "x86_64-linux";
          modules = [
            nixos-hardware.nixosModules.lenovo-thinkpad-t14-intel-gen1
            ./hosts/thinkpad/default.nix
          ];
        };

        thrawny-z13 = mkHost {
          system = "x86_64-linux";
          modules = [
            nixos-hardware.nixosModules.lenovo-thinkpad-z13-gen2
            ./hosts/thrawny-z13/default.nix
          ];
        };

        thrawny-desktop = mkHost {
          system = "x86_64-linux";
          modules = [
            nixos-hardware.nixosModules.common-cpu-amd
            ./hosts/desktop/default.nix
          ];
        };

        thrawny-server = mkHeadlessHost {
          system = "x86_64-linux";
          modules = [
            ./hosts/thrawny-server/default.nix
          ];
        };

        obelisk = mkHeadlessHost {
          system = "x86_64-linux";
          modules = [
            ./hosts/obelisk/default.nix
          ];
        };

        headless = mkHeadlessHost {
          system = "x86_64-linux";
          modules = [
            ./images/headless.nix
          ];
        };
      };

      devShells =
        let
          mkDevShell =
            pkgs:
            pkgs.mkShell {
              packages = with pkgs; [
                pkg-config
                nixd
                nixfmt
                statix
                deadnix
                nvd
                stylua
                selene
                cachix
              ];
            };
        in
        {
          x86_64-linux.default = mkDevShell nixpkgs.legacyPackages.x86_64-linux;
          aarch64-linux.default = mkDevShell nixpkgs.legacyPackages.aarch64-linux;
          aarch64-darwin.default = mkDevShell nixpkgs.legacyPackages.aarch64-darwin;
          x86_64-darwin.default = mkDevShell nixpkgs.legacyPackages.x86_64-darwin;
        };

      formatter =
        let
          mkFormatter =
            pkgs:
            pkgs.writeShellApplication {
              name = "treefmt";
              runtimeInputs = [
                pkgs.treefmt
                pkgs.nixfmt
              ];
              text = ''
                treefmt "$@"
              '';
            };
        in
        {
          x86_64-linux = mkFormatter nixpkgs.legacyPackages.x86_64-linux;
          aarch64-linux = mkFormatter nixpkgs.legacyPackages.aarch64-linux;
          aarch64-darwin = mkFormatter nixpkgs.legacyPackages.aarch64-darwin;
          x86_64-darwin = mkFormatter nixpkgs.legacyPackages.x86_64-darwin;
        };

      homeConfigurations = {
        thrawnym1 = mkHomeConfiguration {
          pkgs = nixpkgs.legacyPackages.aarch64-darwin;
          modules = [ ./home/darwin/default.nix ];
          extraSpecialArgs = import ./hosts/thrawnym1/default.nix;
        };
      };
    };
}
