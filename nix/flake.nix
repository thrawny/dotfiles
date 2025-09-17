{
  description = "NixOS + Hyprland + Home Manager (monorepo) using out-of-store symlinks into this repo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      inherit (builtins) getEnv;
      # Resolve host/user from environment for minimal first-run. You can later edit these.
      host =
        let
          h = getEnv "HOSTNAME";
        in
        if h == "" then "nixos" else h;
      username =
        let
          su = getEnv "SUDO_USER";
          u = getEnv "USER";
        in
        if su != "" then su else (if u != "" then u else "youruser");
      # Auto-detect system for minimal first run (requires --impure on nixos-rebuild)
      system = builtins.currentSystem;
    in
    let
      cfg = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          # Home Manager as a NixOS module
          home-manager.nixosModules.home-manager

          (
            {
              config,
              lib,
              pkgs,
              ...
            }:
            let
              repo = "${
                config.home-manager.users.${username}.home.homeDirectory or "/home/${username}"
              }/dotfiles";
              hwPath = "/etc/nixos/hardware-configuration.nix";
            in
            {
              # Pull in your machine's hardware profile if it exists (falls back in build containers)
              imports = lib.optionals (builtins.pathExists hwPath) [ hwPath ];

              networking.hostName = host;
              system.stateVersion = "25.11"; # set explicitly to silence warnings; adjust if installing older release

              # Wayland desktop with Hyprland via greetd (minimal)
              services.xserver.enable = false; # pure Wayland
              programs.hyprland.enable = true;
              services.greetd.enable = true;
              services.greetd.settings = {
                # For a simple autologin directly into Hyprland.
                # Alternatively: set `initial_session` to Hyprland and `default_session`
                # to a greeter like tuigreet for subsequent logins.
                default_session = {
                  command = "Hyprland";
                  user = username;
                };
              };

              # Shared folder from UTM/QEMU (9p). In UTM, set the shared directory's
              # mount tag to "hostshare" and this will auto-mount at /mnt/host on demand.
              fileSystems."/mnt/host" = {
                device = "hostshare"; # UTM Shared Directory mount tag
                fsType = "9p";
                options = [
                  "trans=virtio"
                  "version=9p2000.L"
                  "msize=262144"
                  "cache=mmap"
                  "rw"
                  "xattr"
                  "nofail"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=600"
                ];
              };

              # Basic bootloader for EFI installs (works for VM + laptop)
              boot.loader.systemd-boot.enable = true;
              boot.loader.efi.canTouchEfiVariables = true;

              # Basic user
              users.users.${username} = {
                isNormalUser = true;
                extraGroups = [
                  "wheel"
                  "video"
                  "audio"
                  "input"
                ];
                shell = pkgs.zsh;
              };

              # Provide zsh at the system level; HM will not manage .zshrc
              programs.zsh.enable = true;

              # Optional: SSH for quick file sync if shared folder isn't available yet
              services.openssh.enable = true;

              # A few helpful tools (trim as desired)
              environment.systemPackages = with pkgs; [
                git
                neovim
                tmux
                ripgrep
                wl-clipboard
                waybar
                foot
                kitty
                fuzzel
              ];

              # Home Manager: map this repo's dotfiles into $HOME (out-of-store symlinks)
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${username} =
                {
                  pkgs,
                  lib,
                  config,
                  ...
                }:
                {
                  home.stateVersion = "24.05"; # bump on HM release upgrades

                  # Source tree path (this repo checked out at ~/dotfiles)
                  # Edit here if you keep the repo elsewhere
                  # NOTE: out-of-store symlinks reflect edits immediately without rebuild
                  home.file.".zshrc".source =
                    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/config/zsh/zshrc";
                  home.file.".tmux.conf".source =
                    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/config/tmux/tmux.conf";
                  home.file.".gitconfig".source =
                    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/config/git/gitconfig";
                  home.file.".gitignoreglobal".source =
                    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/config/git/gitignoreglobal";

                  xdg.configFile."nvim".source =
                    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/config/nvim";
                  xdg.configFile."ghostty".source =
                    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/config/ghostty";
                  xdg.configFile."direnv".source =
                    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/config/direnv";
                  xdg.configFile."k9s".source =
                    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/config/k9s";
                  xdg.configFile."starship/starship.toml".source =
                    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/config/starship/starship.toml";
                  home.file.".default-npm-packages".source =
                    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/config/npm/default-packages";

                  # Hyprland config tracked in this repo (edit config/hypr/hyprland.conf)
                  xdg.configFile."hypr".source =
                    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/config/hypr";

                  # Avoid HM program modules that generate the same targets we link (.zshrc, .gitconfig).
                  # We install tools at the system level instead.
                };
            }
          )
        ];
      };
    in
    {
      nixosConfigurations =
        if host == "nixos" then
          {
            nixos = cfg;
          }
        else
          {
            ${host} = cfg;
            nixos = cfg;
          };
    };
}
