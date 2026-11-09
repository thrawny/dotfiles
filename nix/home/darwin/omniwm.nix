{
  config,
  dotfiles,
  ...
}:
let
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/omniwm/${path}";
in
{
  # OmniWM window manager configuration
  home.file.".config/omniwm/settings.toml".source = link "settings.toml";
  home.file.".config/omniwm/shell/shell.toml".source = link "shell.toml";
  # Forked from the Default profile to hide empty workspaces; see shell.toml.
  home.file.".config/omniwm/shell/widgets/workspaces".source = link "shell-widgets/workspaces";
}
