# Host-side networking for microvms.
# Creates a bridge (microbr) with NAT so guests can reach the internet,
# and matches TAP interfaces created by microvm guests to the bridge.
{
  config,
  lib,
  ...
}:
let
  cfg = config.dotfiles.microvm;
in
{
  options.dotfiles.microvm = {
    enable = lib.mkEnableOption "microvm host networking (bridge + NAT)";

    externalInterface = lib.mkOption {
      type = lib.types.str;
      description = "External network interface for NAT (e.g. eno1, enp6s0).";
    };

    bridgeAddress = lib.mkOption {
      type = lib.types.str;
      default = "192.168.83.1/24";
      description = "IP address/prefix for the microvm bridge.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Bridge device
    systemd.network.enable = true;

    systemd.network.netdevs."20-microbr".netdevConfig = {
      Kind = "bridge";
      Name = "microbr";
    };

    systemd.network.networks."20-microbr" = {
      matchConfig.Name = "microbr";
      addresses = [ { Address = cfg.bridgeAddress; } ];
      networkConfig.ConfigureWithoutCarrier = true;
    };

    # Attach every microvm TAP to the bridge
    systemd.network.networks."21-microvm-tap" = {
      matchConfig.Name = "microvm*";
      networkConfig.Bridge = "microbr";
    };

    # NAT for outbound guest traffic
    networking.nat = {
      enable = true;
      internalInterfaces = [ "microbr" ];
      externalInterface = cfg.externalInterface;
    };

    # Keep NetworkManager away from the bridge & TAPs
    networking.networkmanager.unmanaged = [
      "interface-name:microbr"
      "interface-name:microvm*"
    ];
  };
}
