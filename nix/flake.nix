{
  description = "NixOS + Home Manager (monorepo) using out-of-store symlinks into this repo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Pinned for xwayland 24.1.0 (newer versions crash Steam under xwayland-satellite)
    nixpkgs-xwayland.url = "github:NixOS/nixpkgs/b60793b86201040d9dee019a05089a9150d08b5b";
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
    xremap-flake.url = "github:xremap/nix-flake";
    crane.url = "github:ipetkov/crane";
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
      xremap-flake,
      nixpkgs-xwayland,
      crane,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      # Package builders for cross-architecture support
      mkHyprvoice =
        pkgs:
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

      # Crane-based Rust builds with dependency caching
      mkRustWorkspace =
        pkgs:
        let
          craneLib = crane.mkLib pkgs;
          src = craneLib.cleanCargoSource ../rust;
          commonArgs = {
            inherit src;
            strictDeps = true;
            nativeBuildInputs = with pkgs; [ pkg-config ];
            buildInputs =
              with pkgs;
              lib.optionals stdenv.isLinux [
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
          # Build only dependencies (cached)
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        in
        {
          inherit craneLib commonArgs cargoArtifacts;
        };

      mkAgentSwitch =
        pkgs:
        let
          ws = mkRustWorkspace pkgs;
          featureArgs =
            if pkgs.stdenv.isLinux then "-p agent-switch --features niri" else "-p agent-switch";
        in
        ws.craneLib.buildPackage (
          ws.commonArgs
          // {
            inherit (ws) cargoArtifacts;
            pname = "agent-switch";
            version = "0.1.0";
            cargoExtraArgs = featureArgs;
          }
        );

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

      # Voice-to-text for Wayland - updates via `nix flake update hyprvoice-src`
      packages = {
        x86_64-linux = {
          agent-switch = mkAgentSwitch nixpkgs.legacyPackages.x86_64-linux;
          hyprvoice = mkHyprvoice nixpkgs.legacyPackages.x86_64-linux;
        };
        aarch64-linux = {
          agent-switch = mkAgentSwitch nixpkgs.legacyPackages.aarch64-linux;
          hyprvoice = mkHyprvoice nixpkgs.legacyPackages.aarch64-linux;
        };
        aarch64-darwin = {
          agent-switch = mkAgentSwitch nixpkgs.legacyPackages.aarch64-darwin;
        };
        x86_64-darwin = {
          agent-switch = mkAgentSwitch nixpkgs.legacyPackages.x86_64-darwin;
        };
      };

      # Dev shell - only includes tools not in home.packages
      devShells =
        let
          mkDevShell =
            pkgs:
            pkgs.mkShell {
              packages =
                with pkgs;
                [
                  # Native build dependencies
                  pkg-config

                  # Nix tools (not in packages.nix)
                  nixd
                  nixfmt
                  statix
                  nvd

                  # Lua tools (not in packages.nix)
                  stylua
                  selene
                ]
                ++ lib.optionals stdenv.isLinux [
                  # GTK for agent-switch (Linux only)
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
        in
        {
          x86_64-linux.default = mkDevShell nixpkgs.legacyPackages.x86_64-linux;
          aarch64-linux.default = mkDevShell nixpkgs.legacyPackages.aarch64-linux;
          aarch64-darwin.default = mkDevShell nixpkgs.legacyPackages.aarch64-darwin;
          x86_64-darwin.default = mkDevShell nixpkgs.legacyPackages.x86_64-darwin;
        };

      formatter = {
        x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;
        aarch64-linux = nixpkgs.legacyPackages.aarch64-linux.nixfmt-tree;
        aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt-tree;
        x86_64-darwin = nixpkgs.legacyPackages.x86_64-darwin.nixfmt-tree;
      };

      homeConfigurations = {
        thrawnym1 = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.aarch64-darwin;
          modules = [ ./home/darwin/default.nix ];
          extraSpecialArgs = import ./hosts/thrawnym1/default.nix;
        };

        # Container test configuration (x86_64)
        container-x86_64 = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          modules = [ ./home/container.nix ];
          extraSpecialArgs = {
            username = "root";
            dotfiles = "/root/dotfiles";
          };
        };

        # Container test configuration (aarch64 - for Docker on Mac)
        container = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.aarch64-linux;
          modules = [ ./home/container.nix ];
          extraSpecialArgs = {
            username = "root";
            dotfiles = "/root/dotfiles";
          };
        };

        # Asahi Air with Niri + DankMaterialShell
        # Uses niri installed via DNF, config managed by nix
        thrawny-asahi-air = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.aarch64-linux;
          modules = [
            niri-flake.homeModules.config # config only, no package (using Fedora's niri)
            xremap-flake.homeManagerModules.default
            ./hosts/thrawny-asahi-air/default.nix
          ];
          extraSpecialArgs = {
            inherit self xremap-flake;
            username = "thrawny";
            dotfiles = "/home/thrawny/dotfiles";
            gitIdentity = {
              name = "Jonas Lergell";
              email = "jonaslergell@gmail.com";
            };
          };
        };
      };
    };
}
