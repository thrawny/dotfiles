{ lib, pkgs, ... }:
let
  runnerUser = "forgejo-runner";
  runnerUid = 3104;
  runnerHome = "/var/lib/forgejo-runner";
  runnerConfig = (pkgs.formats.yaml { }).generate "forgejo-runner.yaml" {
    log.level = "info";
    runner = {
      file = "${runnerHome}/.runner";
      capacity = 1;
      timeout = "45m";
      shutdown_timeout = "45m";
      labels = [
        "chalkboard:docker://docker.io/library/node:24-bookworm@sha256:14078204b6bb268c107ceff6d3c43f45a888105e5c2b18b14c32b3409d93a1b0"
      ];
    };
    cache.enabled = false;
    container = {
      # DOCKER_HOST connects the runner to Podman; this setting prevents
      # forwarding that socket into workflow containers.
      docker_host = "-";
      privileged = false;
      valid_volumes = [ ];
      options = "--cpus=2 --memory=3g --memory-swap=3g --pids-limit=512";
      force_pull = true;
    };
  };
in
{
  services.forgejo.settings.actions.ENABLED = true;
  users.groups.${runnerUser} = { };
  users.users.${runnerUser} = {
    uid = runnerUid;
    isSystemUser = true;
    group = runnerUser;
    home = runnerHome;
    createHome = true;
    autoSubUidGidRange = true;
    linger = true;
  };

  systemd.tmpfiles.rules = [ "d ${runnerHome} 0700 ${runnerUser} ${runnerUser} -" ];

  # Podman creates containers in the user's systemd tree, outside the runner
  # service cgroup. Limit the entire account so containers share this budget.
  systemd.slices."user-${toString runnerUid}".sliceConfig = {
    MemoryHigh = "2500M";
    MemoryMax = "3G";
    MemorySwapMax = "0";
    CPUQuota = "200%";
    TasksMax = 1024;
  };

  systemd.user.services.forgejo-runner = {
    description = "Forgejo runner with dedicated rootless Podman";
    wantedBy = [ "default.target" ];
    requires = [ "podman.socket" ];
    after = [ "podman.socket" ];
    unitConfig = {
      ConditionUser = runnerUser;
      ConditionPathExists = "${runnerHome}/.runner";
    };
    path = [
      pkgs.git
      pkgs.podman
    ];
    environment = {
      HOME = runnerHome;
      DOCKER_HOST = "unix:///run/user/${toString runnerUid}/podman/podman.sock";
    };
    serviceConfig = {
      WorkingDirectory = runnerHome;
      ExecStart = "${lib.getExe pkgs.forgejo-runner} daemon --config ${runnerConfig}";
      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStopSec = "46min";
      UMask = "0077";
    };
  };

  environment.systemPackages = [ pkgs.forgejo-runner ];
}
