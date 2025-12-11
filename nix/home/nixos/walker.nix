{ walker, ... }:
{
  imports = [ walker.homeManagerModules.default ];

  programs.walker = {
    enable = true;
    runAsService = true;
  };
}
