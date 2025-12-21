{
  description = "NixOS + Hyprland + Home Manager (monorepo) using out-of-store symlinks into this repo";

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
            inherit zen-browser walker nurPkgs;
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

      # Full dev environment with DIND support
      packages.x86_64-linux.devcontainer =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in
        pkgs.buildEnv {
          name = "devcontainer";
          paths = with pkgs; [
            # Docker + DIND deps
            docker
            containerd
            runc
            iptables
            iproute2

            # Core system tools
            bashInteractive
            coreutils
            findutils
            gnugrep
            gnused
            procps
            util-linux

            # Shell and terminal
            zsh
            tmux
            starship
            zoxide
            fzf
            bat
            direnv

            # Editors
            neovim
            vim

            # Git ecosystem
            git
            git-lfs
            gh
            lazygit
            delta
            difftastic

            # Languages and runtimes
            nodejs_24
            python313
            go
            rustc
            cargo
            bun

            # Language tools
            uv
            pnpm
            golangci-lint
            gotestsum
            ruff
            tree-sitter
            gcc

            # CLI utilities
            jq
            yq-go
            dyff
            tree
            ripgrep
            fd
            curl
            wget
            watch
            watchexec
            ast-grep
            usage
            cowsay

            # Cloud and infra
            awscli2
            k9s
            kind
            postgresql_17
          ];
          pathsToLink = [ "/bin" "/lib" "/share" ];
        };

      homeConfigurations.thrawnym1 = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-darwin;
        modules = [ ./home/darwin/default.nix ];
        extraSpecialArgs = import ./hosts/thrawnym1/default.nix;
      };
    };
}
