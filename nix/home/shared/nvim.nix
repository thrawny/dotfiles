{
  config,
  configPath,
  configSource,
  homeSource,
  lib,
  ...
}:
{
  xdg.configFile."nvim".source = configSource "nvim";

  home.activation = lib.optionalAttrs (homeSource == "store") {
    seedLazyLockfile = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
      dest_path=${lib.escapeShellArg "${config.home.homeDirectory}/.local/state/nvim/lazy-lock.json"}
      if [ ! -s "$dest_path" ]; then
        install -Dm0644 ${lib.escapeShellArg (toString (configPath "nvim/lazy-lock.json"))} "$dest_path"
      fi
    '';
  };

  programs.neovim = {
    enable = true;
  };
}
