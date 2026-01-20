# Minimal container configuration for testing shared modules
{ username, pkgs, ... }:
{
  imports = [ ./shared/default.nix ];

  home = {
    username = username;
    homeDirectory = if username == "root" then "/root" else "/home/${username}";

    # Extra packages needed in containers (normally provided by NixOS system)
    packages = with pkgs; [
      gnutar
      gzip
      findutils
      less
      which
      openssh
      cacert
    ];
  };
}
