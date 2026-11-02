{
  agentAssets,
  config,
  lib,
  pkgs,
  ...
}:
let
  enabledSkillsFor =
    agent:
    builtins.removeAttrs (agentAssets.skillEntriesFor pkgs agent) (
      config.dotfiles.agentSkills.disabled
      ++ (
        if config.dotfiles.agentSkills.herdrTui then
          [ "herdr-core" ]
        else
          [
            "herdr"
            "herdr-demo"
          ]
      )
    );
in
{
  imports = [ ./private-agent-skills.nix ];

  options.dotfiles.agentSkills = {
    disabled = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Skill names to leave out for every agent on this host.";
    };
    herdrTui = lib.mkEnableOption "legacy Herdr TUI skills instead of the herdr-core trigger";
  };

  config.home.file =
    agentAssets.skillFiles "claude" (enabledSkillsFor "claude")
    // agentAssets.skillFiles "codex" (enabledSkillsFor "codex")
    // agentAssets.skillFiles "pi" (enabledSkillsFor "pi");
}
