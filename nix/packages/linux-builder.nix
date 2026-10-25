{ pkgs }:
pkgs.darwin.linux-builder-vz.override {
  modules = [
    ({ pkgs, ... }: {
      # Rosetta on macOS 15 cannot handle the auxv entries added in Linux 6.13.
      boot.kernelPackages = pkgs.linuxPackages_6_12;
    })
    {
      virtualisation.host.pkgs = pkgs.lib.mkForce (
        pkgs.extend (
          _final: prev: {
            # Upstream defaults to the SDK's macOS version, making the cached
            # executable require macOS 27. Target the OS on our builder host.
            vzvm = prev.vzvm.overrideAttrs (old: {
              buildPhase =
                builtins.replaceStrings
                  [ "swiftc -O" ]
                  [
                    "swiftc -O -target arm64-apple-macosx15.0"
                  ]
                  old.buildPhase;
            });
          }
        )
      );
    }
  ];
}
