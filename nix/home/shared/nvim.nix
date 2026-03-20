{
  config,
  lib,
  ...
}@args:
let
  containerAssets = args.containerAssets or null;
  dotfiles = args.dotfiles or null;
  repoBacked = containerAssets == null;
in
{
  xdg.configFile."nvim".source =
    if repoBacked then
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/nvim"
    else
      containerAssets.config + "/nvim";

  home.activation = lib.optionalAttrs (!repoBacked) {
    seedLazyLockfile = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
      dest_path=${lib.escapeShellArg "${config.home.homeDirectory}/.local/state/nvim/lazy-lock.json"}
      if [ ! -s "$dest_path" ]; then
        install -Dm0644 ${
          lib.escapeShellArg (toString (containerAssets.config + "/nvim/lazy-lock.json"))
        } "$dest_path"
      fi
    '';
  };

  programs.neovim = {
    enable = true;
  };
}
