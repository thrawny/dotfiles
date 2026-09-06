{
  config,
  lib,
  llm-agents,
  pkgs,
  self,
  ...
}:
let
  inherit (config.dotfiles) username;
  llmPkgs = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  nvim = self.packages.${pkgs.stdenv.hostPlatform.system}.nvim;
  # Aliases point at the existing configured package, without wrapping it again.
  nvimAliases = pkgs.runCommand "neovim-aliases" { } ''
    mkdir -p "$out/bin"
    ln -s ${lib.getExe nvim} "$out/bin/vi"
    ln -s ${lib.getExe nvim} "$out/bin/vim"
  '';
in
{
  imports = [
    ../../modules/headless.nix
    ../../modules/tailscale-serve.nix
    ../../modules/forgejo.nix
    ../../modules/agents.nix
    ../../modules/t3code.nix
    ./hardware-configuration.nix
    ./disko.nix
  ];

  dotfiles = {
    username = "thrawny";
    homeSource = "store";
    fullName = "Jonas Lergell";
    email = "jonas@lergell.se";
    tailnetDomain = "tailf85bba.ts.net";
  };

  # Keep Herdr's user runtime directory available after the last SSH disconnect.
  users.users.thrawny.linger = true;
  users.users.thrawny.hashedPasswordFile = "/etc/user-password";
  users.users.thrawny.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA2Uiv/7oVuix/LbkSZw4BamMlo0uRYNtr5bRHHUSL5Y jonas@lergell.se"
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA2Uiv/7oVuix/LbkSZw4BamMlo0uRYNtr5bRHHUSL5Y jonas@lergell.se"
  ];

  services.openssh.openFirewall = false;

  services.tailscale = {
    authKeyFile = "/etc/tailscale/auth-key";
    extraUpFlags = [
      "--ssh"
      "--advertise-tags=tag:server"
    ];
  };

  services.tailscaleServe.enable = true;

  networking = {
    hostName = "obelisk";
    firewall = {
      enable = true;
      trustedInterfaces = [ "tailscale0" ];
      extraCommands = ''
        iptables -A nixos-fw -p tcp --dport 22 -s 84.216.114.142/32 -j nixos-fw-accept
      '';
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  environment.systemPackages = with pkgs; [
    btop
    ncurses
    nvim
    (lib.hiPrio nvimAliases)
    (lib.hiPrio ghostty.terminfo)
  ];
  environment.sessionVariables = {
    EDITOR = lib.mkForce "nvim";
    VISUAL = "nvim";
  };

  # T3 Code starts its agents and terminals with a separate systemd PATH.
  systemd.services.t3code = {
    path = [
      nvim
      nvimAliases
    ];
    environment = {
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
  };

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  home-manager.users.${username} = { containerAssets, ... }: {
    imports = [
      ../../home/shared/agent-skills.nix
      ../../home/shared/ai-tools.nix
      ../../home/shared/direnv.nix
      ../../home/shared/herdr.nix
      ../../home/shared/theme.nix
      ../../home/shared/bash.nix
      ../../home/shared/zsh.nix
      ../../home/shared/git.nix
      ../../home/shared/starship.nix
      ../../home/shared/zmx.nix
    ];

    programs.home-manager.enable = true;

    home = {
      stateVersion = "24.05";
      inherit username;
      homeDirectory = "/home/${username}";
      packages = with pkgs; [
        llmPkgs.claude-code
        llmPkgs.codex
        llmPkgs.pi
        # Runtimes for the shared agent hooks, extensions, and package installs.
        bun
        jq
        just
        nodejs_24
        pnpm_11
        python3
        uv
        ncurses
        (lib.hiPrio ghostty.terminfo)
      ];
      sessionPath = [
        "${containerAssets.bin}"
        "$HOME/.local/bin"
      ];
      sessionVariables = {
        LANG = "en_US.UTF-8";
        LC_ALL = "en_US.UTF-8";
        COLORTERM = "truecolor";
      };
    };
  };
}
