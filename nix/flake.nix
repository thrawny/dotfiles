{
  description = "NixOS + Home Manager (monorepo) using out-of-store symlinks into this repo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Pinned for xwayland 24.1.0 (newer versions crash Steam under xwayland-satellite)
    nixpkgs-xwayland.url = "github:NixOS/nixpkgs/b60793b86201040d9dee019a05089a9150d08b5b";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    lazy-nvim-nix.url = "github:josh/lazy-nvim-nix";
    lazy-nvim-nix.inputs.nixpkgs.follows = "nixpkgs";
    nvim-auto-save = {
      url = "github:okuuva/auto-save.nvim";
      flake = false;
    };
    nvim-baml-syntax = {
      url = "github:klepp0/nvim-baml-syntax";
      flake = false;
    };
    nvim-codediff = {
      url = "github:thrawny/codediff.nvim";
      flake = false;
    };
    nvim-git-conflict = {
      url = "github:akinsho/git-conflict.nvim";
      flake = false;
    };
    nvim-monokai-pro = {
      url = "github:loctvl842/monokai-pro.nvim";
      flake = false;
    };
    nvim-tmux-navigator = {
      url = "github:christoomey/vim-tmux-navigator";
      flake = false;
    };
    hunk.url = "github:modem-dev/hunk";
    nix-index-database.url = "github:Mic92/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nur.url = "github:nix-community/NUR";
    helium-browser.url = "github:schembriaiden/helium-browser-nix-flake";
    helium-browser.inputs.nixpkgs.follows = "nixpkgs";
    linux-systems.url = "github:nix-systems/default-linux";
    elephant.url = "github:abenz1267/elephant";
    walker.url = "github:abenz1267/walker";
    walker.inputs.elephant.follows = "elephant";
    niri-flake.url = "github:epireyn/niri-flake";
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
    cursor-plugins = {
      url = "github:cursor/plugins";
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
      lazy-nvim-nix,
      nvim-auto-save,
      nvim-baml-syntax,
      nvim-codediff,
      nvim-git-conflict,
      nvim-monokai-pro,
      nvim-tmux-navigator,
      hunk,
      nix-index-database,
      nixos-hardware,
      nur,
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
      cursor-plugins,
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
          cursor-plugins
          lib
          mattpocock-skills
          ;
        containerAssets = storeHomeAssets;
      };
      flakeArgs = {
        inherit
          agentAssets
          hunk
          lazy-nvim-nix
          llm-agents
          nix-index-database
          nvim-auto-save
          nvim-baml-syntax
          nvim-codediff
          nvim-git-conflict
          nvim-monokai-pro
          nvim-tmux-navigator
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

      packages =
        lib.genAttrs
          [
            "x86_64-linux"
            "aarch64-linux"
            "aarch64-darwin"
          ]
          (
            system:
            let
              pkgs = nixpkgs.legacyPackages.${system};
            in
            {
              nvim = import ./lib/nvim-package.nix {
                inherit
                  lazy-nvim-nix
                  nvim-auto-save
                  nvim-baml-syntax
                  nvim-codediff
                  nvim-git-conflict
                  nvim-monokai-pro
                  nvim-tmux-navigator
                  pkgs
                  ;
              };
            }
          );

      homeConfigurations = {
        thrawnym1 = mkHomeConfiguration {
          pkgs = nixpkgs.legacyPackages.aarch64-darwin;
          modules = [ ./home/darwin/default.nix ];
          extraSpecialArgs = import ./hosts/thrawnym1/default.nix;
        };
      };
    };
}
