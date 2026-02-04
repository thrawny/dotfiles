# Microvm declarations for thrawny-desktop.
#
# Each VM is an ephemeral NixOS guest with the headless server setup
# (zsh, neovim, tmux, git, etc.) — ideal for running coding agents
# without giving them access to personal files.
#
# Usage:
#   mkdir -p ~/microvm/<project>/ssh-host-keys
#   ssh-keygen -t ed25519 -N "" -f ~/microvm/<project>/ssh-host-keys/ssh_host_ed25519_key
#   sudo systemctl start microvm@<vmname>
#   ssh 192.168.83.<ip>
{
  config,
  lib,
  pkgs,
  self,
  microvm,
  homeManagerModule,
  ...
}:
let
  inherit (config.dotfiles) username;
  userHome = "/home/${username}";

  microvmGuest = import ../../modules/microvm/guest.nix {
    inherit self homeManagerModule;
  };
in
{
  imports = [ ../../modules/microvm/host.nix ];

  dotfiles.microvm = {
    enable = true;
    # TODO: verify your desktop's external interface (ip link show)
    externalInterface = "eno1";
  };

  # ── Example: generic coding-agent VM ──────────────────────────────────
  # Duplicate this block and adjust hostName/ipAddress/tapId/mac/workspace
  # to create additional project-specific VMs.
  microvm.vms.agent = {
    autostart = false;

    config = {
      imports = [
        microvm.nixosModules.microvm
        (microvmGuest {
          hostName = "agent";
          ipAddress = "192.168.83.2";
          tapId = "microvm0";
          mac = "02:00:00:00:00:01";
          workspace = "${userHome}/microvm/agent";
          dotfilesPath = "${userHome}/dotfiles";
          # Uncomment to share Claude credentials into the VM:
          # claudeCredentialsPath = "${userHome}/claude-microvm";
          extraPackages = with pkgs; [
            nodejs_24
            python313
            uv
            go
            rustc
            cargo
          ];
        })
      ];
    };
  };
}
