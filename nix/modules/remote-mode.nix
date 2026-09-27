{ pkgs, ... }:
let
  command = pkgs.writeShellApplication {
    name = "remote-mode";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
      util-linux
    ];
    text = builtins.readFile ../../bin/remote-mode;
  };
  holdAwake = pkgs.writeShellScript "remote-mode-hold" ''
    set -e
    # systemd-inhibit clears NOTIFY_SOCKET in its child environment.
    export NOTIFY_SOCKET="$1"
    ${pkgs.systemd}/bin/systemd-notify --ready
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';
in
{
  environment.systemPackages = [ command ];

  # The root-owned marker remembers the mode independently of user sessions.
  systemd.services.remote-mode = {
    description = "Keep the machine available for remote access";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-logind.service" ];
    requires = [ "systemd-logind.service" ];
    unitConfig.ConditionPathExists = "/var/lib/remote-mode/enabled";
    # Sleep only: hypridle must still lock the screen and turn monitors off.
    script = ''
      exec ${pkgs.systemd}/bin/systemd-inhibit --what=sleep --mode=block --who=remote-mode --why=Remote-access ${holdAwake} "$NOTIFY_SOCKET"
    '';
    serviceConfig = {
      Type = "notify";
      NotifyAccess = "all";
      TimeoutStartSec = "15s";
      Restart = "on-failure";
      RestartSec = "2s";
      StateDirectory = "remote-mode";
      StateDirectoryMode = "0755";
    };
  };
}
