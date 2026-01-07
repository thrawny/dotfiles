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
    hyprvoice-src = {
      url = "github:LeonardoTrapani/hyprvoice";
      flake = false;
    };
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
      hyprvoice-src,
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
      };

      packages = {
        x86_64-linux = {
          niri-switcher =
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
          # Voice-to-text for Wayland - updates via `nix flake update hyprvoice-src`
          hyprvoice =
            let
              pkgs = nixpkgs.legacyPackages.x86_64-linux;
            in
            pkgs.buildGoModule {
              pname = "hyprvoice";
              version = hyprvoice-src.shortRev or "unstable";
              src = hyprvoice-src;
              vendorHash = "sha256-qYZGccprn+pRbpVeO1qzSOb8yz/j/jdzPMxFyIB9BNA=";
              doCheck = false; # Tests require wl-copy, wtype etc.
              nativeBuildInputs = with pkgs; [
                pkg-config
                makeWrapper
              ];
              buildInputs = with pkgs; [
                pipewire
                alsa-lib
              ];
              postInstall = ''
                wrapProgram $out/bin/hyprvoice \
                  --prefix PATH : ${
                    pkgs.lib.makeBinPath (
                      with pkgs;
                      [
                        pipewire
                        wl-clipboard
                        wtype
                      ]
                    )
                  }
              '';
              meta = {
                description = "Voice-to-text for Wayland/Hyprland";
                homepage = "https://github.com/LeonardoTrapani/hyprvoice";
                mainProgram = "hyprvoice";
              };
            };
        };
        aarch64-linux =
          let
            pkgs = nixpkgs.legacyPackages.aarch64-linux;
          in
          {
            niri-switcher = pkgs.rustPlatform.buildRustPackage {
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
            hyprvoice = pkgs.buildGoModule {
              pname = "hyprvoice";
              version = hyprvoice-src.shortRev or "unstable";
              src = hyprvoice-src;
              vendorHash = "sha256-qYZGccprn+pRbpVeO1qzSOb8yz/j/jdzPMxFyIB9BNA=";
              doCheck = false; # Tests require wl-copy, wtype etc.
              nativeBuildInputs = with pkgs; [
                pkg-config
                makeWrapper
              ];
              buildInputs = with pkgs; [
                pipewire
                alsa-lib
              ];
              postInstall = ''
                wrapProgram $out/bin/hyprvoice \
                  --prefix PATH : ${
                    pkgs.lib.makeBinPath (
                      with pkgs;
                      [
                        pipewire
                        wl-clipboard
                        wtype
                      ]
                    )
                  }
              '';
              meta = {
                description = "Voice-to-text for Wayland/Hyprland";
                homepage = "https://github.com/LeonardoTrapani/hyprvoice";
                mainProgram = "hyprvoice";
              };
            };
          };
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
