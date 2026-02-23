{
  config,
  ...
}:
{
  # Configure npm to use a writable directory for global packages
  home.file.".npmrc".text = ''
    prefix = ${config.home.homeDirectory}/.npm-global
  '';
}
