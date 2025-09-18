{ lib, ... }:
{
  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "mode=0755" "size=2G" ];
  };

  fileSystems."/mnt/host" = {
    device = "hostshare";
    fsType = "9p";
    options = [
      "trans=virtio"
      "version=9p2000.L"
      "msize=262144"
      "cache=mmap"
      "rw"
      "xattr"
      "nofail"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
    ];
  };

  swapDevices = [ ];

  assertions = [
    {
      assertion = lib.versionAtLeast lib.version "0"; # keep the module non-empty
      message = "tester hardware stub should be replaced if you rely on persistent storage";
    }
  ];
}
