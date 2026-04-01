{
  lib,
  config,
  pkgs,
  ...
}:
{
  boot = {
    extraModprobeConfig = lib.mkAfter ''
      options mt7921e disable_aspm=Y
    '';
    resumeDevice = "/dev/mapper/luks-4d3e8b23-c336-4111-9c1c-ee5ec021e465";
    kernelParams = [ "resume_offset=351778816" ];
  };

  services = {
    # Lid close: plain suspend. Manual hibernate remains available.
    logind.settings.Login.HandleLidSwitch = "suspend";

    # Hibernate when battery is critical (safety net for clamshell + unplug scenario).
    upower = {
      enable = true;
      percentageLow = 20;
      percentageCritical = 10;
      percentageAction = 5;
      criticalPowerAction = "Hibernate";
    };
  };

  # Swapfile for hibernate (must be >= RAM size).
  swapDevices = [
    {
      device = "/swapfile";
      size = 65536; # 64 GiB
    }
  ];

  # Keep NixOS's generated pre-sleep/pre-shutdown wrappers as valid no-op units.
  # Without this, systemd gets empty oneshot services and logs bad-setting errors.
  powerManagement.powerDownCommands = ":";

  # mt7921e fails to restore reliably from hibernate on some systems.
  # Unload it before sleep and reprobe it after wake to avoid the broken
  # PCIe resume path entirely.
  systemd.services.mt7921e-sleep = {
    description = "Remove mt7921e before sleep";
    wantedBy = [ "sleep.target" ];
    before = [ "sleep.target" ];
    unitConfig = {
      DefaultDependencies = false;
      StopWhenUnneeded = true;
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "-${pkgs.kmod}/bin/modprobe -r mt7921e";
      ExecStop = "${pkgs.kmod}/bin/modprobe mt7921e";
    };
  };

}
