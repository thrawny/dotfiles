{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.dotfiles) username;
  uid = toString config.users.users.${username}.uid;

  niriLidOutput = pkgs.writeShellScript "niri-lid-output" ''
    set -euo pipefail

    lid_state="$(${pkgs.gnugrep}/bin/grep -h -o 'open\|closed' /proc/acpi/button/lid/*/state | ${pkgs.coreutils}/bin/head -1 || true)"
    case "$lid_state" in
      open) output_state=on ;;
      closed) output_state=off ;;
      *) exit 0 ;;
    esac

    niri_socket="$(${pkgs.findutils}/bin/find /run/user/${uid} -maxdepth 1 -type s -name 'niri.*.sock' -printf '%T@ %p\n' 2>/dev/null \
      | ${pkgs.coreutils}/bin/sort -nr \
      | ${pkgs.coreutils}/bin/head -1 \
      | ${pkgs.gawk}/bin/awk '{print $2}')"

    [[ -n "$niri_socket" ]] || exit 0

    exec ${pkgs.util-linux}/bin/runuser -u ${username} -- \
      ${pkgs.coreutils}/bin/env \
        XDG_RUNTIME_DIR=/run/user/${uid} \
        NIRI_SOCKET="$niri_socket" \
        ${config.programs.niri.package}/bin/niri msg output eDP-1 "$output_state"
  '';
in
{
  boot = {
    extraModprobeConfig = lib.mkAfter ''
      options mt7921e disable_aspm=Y
    '';
    resumeDevice = "/dev/mapper/luks-4d3e8b23-c336-4111-9c1c-ee5ec021e465";
    kernelParams = [ "resume_offset=351778816" ];
  };

  services = {
    # Lid close is handled by acpid below. Suspend remains manual,
    # plus the critical battery safety net below.
    logind.settings.Login = {
      HandleLidSwitch = "ignore";
      HandleLidSwitchDocked = "ignore";
      HandleLidSwitchExternalPower = "ignore";
    };

    # In niri, a closed laptop panel can still be focusable unless the output is
    # disabled. Keep eDP-1 in sync with the physical lid state.
    acpid = {
      enable = true;
      handlers.niri-lid-output = {
        event = "button/lid.*";
        action = "${niriLidOutput}";
      };
    };

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
