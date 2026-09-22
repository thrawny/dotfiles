{
  config,
  ...
}:
{
  # Configure npm to use a writable directory for global packages
  home.file.".npmrc".text = ''
    prefix = ${config.home.homeDirectory}/.npm-global
    ignore-scripts = true

    # Token comes from NPM_TOKEN, exported by ~/.secrets, so it stays out of
    # the world-readable nix store.
    //npm.pkg.github.com/:_authToken=''${NPM_TOKEN}
  '';

  # Prevent Bun installs from running lifecycle scripts by default.
  home.file.".bunfig.toml".text = ''
    [install]
    ignoreScripts = true
  '';
}
