# Base microvm guest configuration.
#
# Two-level curried function:
#   1. Flake-level inputs  →  { self, homeManagerModule }
#   2. Per-VM parameters   →  { hostName, ipAddress, … }
#   Returns a NixOS module that can be imported in microvm.vms.<name>.config.
{
  self,
  homeManagerModule,
}:
{
  hostName,
  ipAddress,
  tapId,
  mac,
  workspace,
  username ? "thrawny",
  fullName ? "Jonas Lergell",
  email ? "jonaslergell@gmail.com",
  vcpu ? 8,
  mem ? 4096,
  varSize ? 8192,
  claudeCredentialsPath ? null, # e.g. "/home/thrawny/claude-microvm"
  dotfilesPath ? null, # e.g. "/home/thrawny/dotfiles"
  extraPackages ? [ ],
  extraZshInit ? "",
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  userHome = "/home/${username}";
  dotfiles = "${userHome}/dotfiles";
  gitIdentity = {
    name = fullName;
    inherit email;
  };

  claudeShares = lib.optionals (claudeCredentialsPath != null) [
    {
      proto = "virtiofs";
      tag = "claude-credentials";
      source = claudeCredentialsPath;
      mountPoint = "${userHome}/claude-credentials";
    }
  ];

  dotfilesShares = lib.optionals (dotfilesPath != null) [
    {
      proto = "virtiofs";
      tag = "dotfiles";
      source = dotfilesPath;
      mountPoint = dotfiles;
    }
  ];
in
{
  imports = [
    homeManagerModule
  ];

  # ── Networking ────────────────────────────────────────────────────────
  services.resolved.enable = true;

  networking = {
    inherit hostName;
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = false;
  };

  systemd.network.networks."10-e" = {
    matchConfig.Name = "e*";
    addresses = [ { Address = "${ipAddress}/24"; } ];
    routes = [ { Gateway = "192.168.83.1"; } ];
  };

  # ── Hypervisor & shares ───────────────────────────────────────────────
  microvm = {
    interfaces = [
      {
        type = "tap";
        id = tapId;
        inherit mac;
      }
    ];

    hypervisor = "cloud-hypervisor";
    inherit vcpu mem;
    socket = "control.socket";

    writableStoreOverlay = "/nix/.rw-store";

    volumes = [
      {
        mountPoint = "/var";
        image = "var.img";
        size = varSize;
      }
    ];

    shares =
      [
        {
          proto = "virtiofs";
          tag = "ro-store";
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
        }
        {
          proto = "virtiofs";
          tag = "ssh-keys";
          source = "${workspace}/ssh-host-keys";
          mountPoint = "/etc/ssh/host-keys";
        }
        {
          proto = "virtiofs";
          tag = "workspace";
          source = workspace;
          mountPoint = workspace;
        }
      ]
      ++ claudeShares
      ++ dotfilesShares;
  };

  # ── SSH ───────────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    hostKeys = [
      {
        path = "/etc/ssh/host-keys/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  # Workaround: let the nix-store mount stop without blocking shutdown
  systemd.mounts = [
    {
      what = "store";
      where = "/nix/store";
      overrideStrategy = "asDropin";
      unitConfig.DefaultDependencies = false;
    }
  ];

  # ── System ────────────────────────────────────────────────────────────
  system.stateVersion = "25.11";
  time.timeZone = "Europe/Stockholm";
  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  users.users.${username} = {
    isNormalUser = true;
    home = userHome;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOR81cTVFr3icJMAzTqmRU/D5oZSbZanTquggDRcOsZJ jonaslergell@gmail.com"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  programs = {
    zsh = {
      enable = true;
      enableGlobalCompInit = false;
    };
    direnv.enable = true;
  };

  environment.systemPackages =
    with pkgs;
    [
      curl
      fd
      git
      gnumake
      neovim
      ripgrep
      tmux
      wget
      unzip
      claude-code
    ]
    ++ extraPackages;

  # ── Home Manager (reuses headless config) ─────────────────────────────
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = {
      inherit
        self
        dotfiles
        username
        gitIdentity
        ;
    };
    users.${username} = import ../../home/nixos/headless.nix;
  };

  # Optional extra zsh init (e.g. project-specific env vars)
  programs.zsh.interactiveShellInit = lib.mkIf (extraZshInit != "") extraZshInit;
}
