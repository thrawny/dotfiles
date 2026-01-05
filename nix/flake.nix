{
  description = "NixOS + Home Manager (monorepo) using out-of-store symlinks into this repo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nur.url = "github:nix-community/NUR";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";
    elephant.url = "github:abenz1267/elephant";
    walker.url = "github:abenz1267/walker";
    walker.inputs.elephant.follows = "elephant";
    niri-flake.url = "github:sodiboo/niri-flake";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nixos-hardware,
      nur,
      zen-browser,
      walker,
      niri-flake,
      ...
    }:
    let
      inherit (nixpkgs) lib;
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
              ;
          };
          modules = [
            home-manager.nixosModules.home-manager
            niri-flake.nixosModules.niri # cached niri package + system setup
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

      packages.x86_64-linux.niri-switcher =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in
        pkgs.rustPlatform.buildRustPackage {
          pname = "niri-switcher";
          version = "0.1.0";
          src = ../niri-switcher;
          cargoLock.lockFile = ../niri-switcher/Cargo.lock;
          nativeBuildInputs = with pkgs; [ pkg-config ];
          buildInputs = with pkgs; [
            gtk4
            gtk4-layer-shell
            glib
            cairo
            pango
            gdk-pixbuf
            graphene
            harfbuzz
          ];
        };

      packages.aarch64-linux.niri-switcher =
        let
          pkgs = nixpkgs.legacyPackages.aarch64-linux;
        in
        pkgs.rustPlatform.buildRustPackage {
          pname = "niri-switcher";
          version = "0.1.0";
          src = ../niri-switcher;
          cargoLock.lockFile = ../niri-switcher/Cargo.lock;
          nativeBuildInputs = with pkgs; [ pkg-config ];
          buildInputs = with pkgs; [
            gtk4
            gtk4-layer-shell
            glib
            cairo
            pango
            gdk-pixbuf
            graphene
            harfbuzz
          ];
        };

      devShells.x86_64-linux.gtk =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in
        pkgs.mkShell {
          packages = with pkgs; [
            python3
            python3Packages.pygobject3
            gtk4
            gtk4-layer-shell
            gobject-introspection
          ];
          shellHook = ''
            export LD_PRELOAD=${pkgs.gtk4-layer-shell}/lib/libgtk4-layer-shell.so
          '';
        };

      devShells.x86_64-linux.niri-switcher =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in
        pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            pkg-config
            rustc
            cargo
          ];
          buildInputs = with pkgs; [
            gtk4
            gtk4-layer-shell
            glib
            cairo
            pango
            gdk-pixbuf
            graphene
            harfbuzz
          ];
        };

      homeConfigurations.thrawnym1 = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-darwin;
        modules = [ ./home/darwin/default.nix ];
        extraSpecialArgs = import ./hosts/thrawnym1/default.nix;
      };

      # Asahi Air with Niri + DankMaterialShell
      # Uses niri installed via DNF, config managed by nix
      homeConfigurations.thrawny-asahi-air = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-linux;
        modules = [
          niri-flake.homeModules.config # config only, no package (using Fedora's niri)
          ./hosts/thrawny-asahi-air/default.nix
        ];
        extraSpecialArgs = {
          inherit self;
          username = "thrawny";
          dotfiles = "/home/thrawny/dotfiles";
          gitIdentity = {
            name = "Jonas Lergell";
            email = "jonaslergell@gmail.com";
          };
        };
      };
    };
}
