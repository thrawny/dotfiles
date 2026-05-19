{
  config,
  ...
}:
{
  # Configure npm to use a writable directory for global packages
  home.file.".npmrc".text = ''
    prefix = ${config.home.homeDirectory}/.npm-global
    ignore-scripts = true
  '';

  # Prevent Bun installs from running lifecycle scripts by default.
  home.file.".bunfig.toml".text = ''
    [install]
    ignoreScripts = true
  '';
}
