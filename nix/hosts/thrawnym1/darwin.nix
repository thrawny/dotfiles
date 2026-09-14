_:
let
  host = import ./default.nix;
in
{
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 6;
  system.primaryUser = host.username;
  networking.hostName = "thrawnym1";
  networking.localHostName = "thrawnym1";
  users.users.${host.username}.home = "/Users/${host.username}";

  # Determinate continues to own the Nix daemon and nix.conf.
  nix.enable = false;
  programs.zsh.enable = true;

  services.tailscale.enable = true;
  launchd.daemons.tailscaled.serviceConfig.KeepAlive = true;

}
