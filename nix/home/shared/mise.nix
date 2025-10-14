{ config, ... }:
let
  homeDir = config.home.homeDirectory;
in
{
  programs.mise = {
    enable = true;
    enableZshIntegration = false;
    globalConfig = {
      settings = {
        trusted_config_paths = [
          "${homeDir}/dotfiles"
          "${homeDir}/code"
        ];
        idiomatic_version_file_enable_tools = [
          "python"
          "node"
        ];
      };
    };
  };
}
