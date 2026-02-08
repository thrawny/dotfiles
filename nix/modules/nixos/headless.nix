{ ... }:
{
  imports = [
    ./system.nix
  ];

  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;
  documentation.enable = false;

  # Keep server generations lean on hosts using GRUB.
  boot.loader.grub.configurationLimit = 2;

  # Safety net for transient memory spikes (Nix eval/build, service restarts).
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  # Prefer RAM, but allow swapping before OOM under bursty load.
  boot.kernel.sysctl."vm.swappiness" = 100;

  nix = {
    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 1d";
    };
    optimise.automatic = true;
    settings = {
      keep-derivations = false;
      keep-outputs = false;
    };
  };
}
