{
  description = "NixOS + Home Manager (monorepo) using out-of-store symlinks into this repo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Pinned for xwayland 24.1.0 (newer versions crash Steam under xwayland-satellite)
    nixpkgs-xwayland.url = "github:NixOS/nixpkgs/b60793b86201040d9dee019a05089a9150d08b5b";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    hunk.url = "github:modem-dev/hunk";
    hunk.inputs.bun2nix.inputs.systems.follows = "linux-systems";
    nix-index-database.url = "github:Mic92/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nur.url = "github:nix-community/NUR";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";
    helium-browser.url = "github:schembriaiden/helium-browser-nix-flake";
    helium-browser.inputs.nixpkgs.follows = "nixpkgs";
    linux-systems.url = "github:nix-systems/default-linux";
    elephant.url = "github:abenz1267/elephant";
    walker.url = "github:abenz1267/walker";
    walker.inputs.elephant.follows = "elephant";
    niri-flake.url = "github:sodiboo/niri-flake";
    niri-flake.inputs.niri-stable.url = "github:niri-wm/niri/v26.04";
    xremap-flake.url = "github:xremap/nix-flake";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    srvos.url = "github:nix-community/srvos";
    srvos.inputs.nixpkgs.follows = "nixpkgs";
    llm-agents.url = "github:numtide/llm-agents.nix";
    hermes-agent.url = "github:NousResearch/hermes-agent";
    thrawny-pkgs = {
      url = "github:thrawny/nix-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zmx.url = "github:thrawny/zmx-flake";
    acpx-skills = {
      url = "github:openclaw/acpx";
      flake = false;
    };
    agent-browser = {
      url = "github:vercel-labs/agent-browser";
      flake = false;
    };
    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };
    anthropic-skills = {
      url = "github:anthropics/skills";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      hunk,
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
      llm-agents,
      hermes-agent,
      thrawny-pkgs,
      zmx,
      acpx-skills,
      agent-browser,
      mattpocock-skills,
      anthropic-skills,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      storeHomeAssets = {
        config = builtins.path {
          path = ../config;
          name = "dotfiles-config";
        };
        skills = builtins.path {
          path = ../skills;
          name = "dotfiles-skills";
        };
        rules = builtins.path {
          path = ../rules;
          name = "dotfiles-rules";
        };
        bin = builtins.path {
          path = ../bin;
          name = "dotfiles-bin";
        };
      };
      agentAssets = import ./lib/agent-skills.nix {
        inherit
          acpx-skills
          agent-browser
          anthropic-skills
          lib
          mattpocock-skills
          ;
        containerAssets = storeHomeAssets;
      };
      flakeArgs = {
        inherit
          agentAssets
          hunk
          llm-agents
          nix-index-database
          thrawny-pkgs
          zmx
          ;
        containerAssets = storeHomeAssets;
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
              llm-agents
              hermes-agent
              agentAssets
              thrawny-pkgs
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
                # niri-flake's stable package still applies a pre-26.04 service
                # patch that expects /usr/bin in niri.service. niri 26.04 no
                # longer needs it, and the patch fails the build.
                (_: prev: {
                  niri-stable = prev.niri-stable.override {
                    replace-service-with-usr-bin = false;
                  };
                })
                # Use the current pnpm 10 with the git-dependency CVE fixes for vesktop.
                (final: prev: {
                  vesktop = prev.vesktop.override { inherit (final) pnpm_10; };
                })
              ];
            }
            {
              home-manager.extraSpecialArgs = flakeArgs;
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
              llm-agents
              hermes-agent
              agentAssets
              thrawny-pkgs
              zen-browser
              walker
              nurPkgs
              xremap-flake
              zmx
              ;
          };
          modules = [
            srvos.nixosModules.server
            srvos.nixosModules.mixins-trusted-nix-caches
            home-manager.nixosModules.home-manager
            disko.nixosModules.disko
            zmx.nixosModules.cache
            hermes-agent.nixosModules.default
            {
              home-manager.extraSpecialArgs = flakeArgs;
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
            ./modules/nixos/docker.nix
          ];
        };

        headless-docker = mkHeadlessHost {
          system = "x86_64-linux";
          modules = [
            ./images/headless.nix
            ./modules/nixos/docker.nix
          ];
        };

        headless-podman = mkHeadlessHost {
          system = "x86_64-linux";
          modules = [
            ./images/headless.nix
            ./modules/nixos/podman.nix
          ];
        };
      };

      devShells =
        let
          mkDevShell =
            pkgs:
            pkgs.mkShell {
              packages = with pkgs; [
                bashInteractive
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
