{
  config,
  configSource,
  lib,
  pkgs,
  rex,
  ...
}:
let
  cfg = config.dotfiles.rex;
in
{
  imports = [ rex.homeManagerModules.default ];

  options.dotfiles.rex = {
    enable = lib.mkEnableOption "the Rex CLI and the shared init.lua";
    server = lib.mkEnableOption "a personal Rex server that clients reach over SSH (Linux)";
  };

  config = lib.mkIf cfg.enable {
    programs.rex.enable = true;
    # The guard needs programs.ssh, and ~/.ssh/config is hand-owned. Without
    # it Rex terminals keep TERM=xterm-256color, which every host knows.
    programs.rex.sshGuard = false;
    services.rex.enable = cfg.server;

    # Mutable, so `rex config reload` applies an edit without a switch.
    xdg.configFile."rex/init.lua" = {
      source = configSource "rex/init.lua";
      # Replace a hand-made copy instead of failing activation.
      force = true;
    };

    # Rex puts the running server's own rex first on PATH in its terminals.
    # The macOS profile above re-prepends the Nix profile, which would put this
    # pinned CLI ahead of the app's newer one, so restore Rex's choice.
    programs.zsh.profileExtra = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
      lib.mkAfter ''
        if [ -n "''${REX_BIN_DIR:-}" ]; then
          path=("$REX_BIN_DIR" $path)
        fi
      ''
    );
  };
}
