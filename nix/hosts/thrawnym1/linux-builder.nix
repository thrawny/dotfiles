{
  config,
  lib,
  pkgs,
  ...
}:
let
  builder = import ../../packages/linux-builder.nix { inherit pkgs; };
  builderConfig = pkgs.writeText "linux-builder.conf" ''
    builders = ssh-ng://builder@linux-builder aarch64-linux,x86_64-linux /etc/nix/builder_ed25519 2 1 benchmark,big-parallel - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUpCV2N4Yi9CbGFxdDFhdU90RStGOFFVV3JVb3RpQzVxQkorVXVFV2RWQ2Igcm9vdEBuaXhvcwo=
    builders-use-substitutes = true
  '';
in
{
  # The standard nix.linux-builder module requires nix.enable; Determinate owns
  # our daemon instead. Keep its nix.conf and include our builder separately.
  environment.etc."nix/linux-builder.conf".source = builderConfig;
  environment.etc."ssh/ssh_config.d/100-linux-builder.conf".text = ''
    Host linux-builder
      Hostname 127.0.0.1
      HostKeyAlias linux-builder
      Port 31022
      User builder
      IdentityFile /etc/nix/builder_ed25519
  '';

  system.activationScripts.preActivation.text = lib.mkAfter ''
    mkdir -p /var/lib/linux-builder
  '';

  system.activationScripts.postActivation.text = lib.mkAfter ''
    touch /etc/nix/nix.custom.conf
    if ! ${pkgs.gnugrep}/bin/grep -qxF '!include /etc/nix/linux-builder.conf' /etc/nix/nix.custom.conf; then
      printf '\n!include /etc/nix/linux-builder.conf\n' >> /etc/nix/nix.custom.conf
    fi
    launchctl kickstart -k system/systems.determinate.nix-daemon
  '';

  launchd.daemons.linux-builder = {
    environment.NIX_SSL_CERT_FILE = config.environment.variables.NIX_SSL_CERT_FILE;
    script = ''
      export TMPDIR=/run/org.nixos.linux-builder USE_TMPDIR=1
      mkdir -p "$TMPDIR"
      exec ${builder}/bin/create-builder
    '';
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = true;
      WorkingDirectory = "/var/lib/linux-builder";
      StandardOutPath = "/var/log/linux-builder.log";
      StandardErrorPath = "/var/log/linux-builder.log";
    };
  };
}
