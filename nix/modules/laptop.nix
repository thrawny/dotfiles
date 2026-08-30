{
  lib,
  ...
}:
{
  # Laptop defaults: battery-aware power management with minimal host-specific tuning.
  services = {
    fwupd.enable = lib.mkDefault true;

    # TLP handles automatic AC/BAT profile transitions.
    tlp = {
      enable = lib.mkDefault true;
      settings = {
        CPU_SCALING_GOVERNOR_ON_AC = lib.mkDefault "powersave";
        CPU_SCALING_GOVERNOR_ON_BAT = lib.mkDefault "powersave";

        CPU_ENERGY_PERF_POLICY_ON_AC = lib.mkDefault "balance_power";
        CPU_ENERGY_PERF_POLICY_ON_BAT = lib.mkDefault "power";

        WIFI_PWR_ON_AC = lib.mkDefault "off";
        WIFI_PWR_ON_BAT = lib.mkDefault "on";
      };
    };

    # Avoid overlapping power managers.
    power-profiles-daemon.enable = lib.mkForce false;
  };
}
