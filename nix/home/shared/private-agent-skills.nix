{
  agentAssets,
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.privateAgentSkills;
  syncCommand = pkgs.writeShellApplication {
    name = "private-skills-sync";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh
    ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../../../bin/private-skills-sync} \
        --config ${lib.escapeShellArg "${config.xdg.configHome}/private-agent-skills/config.json"} "$@"
    '';
  };
in
{
  options.dotfiles.privateAgentSkills = {
    enable = lib.mkEnableOption "private agent skills synced from Forgejo at activation";
    repository = lib.mkOption {
      type = lib.types.str;
      default = "https://forgejo.tailf85bba.ts.net/thrawny/private-agent-skills";
      description = "Private Git repository URL. Credentials stay in the user's Git credential helper.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ syncCommand ];
    xdg.configFile."private-agent-skills/config.json".text = builtins.toJSON {
      inherit (cfg) repository;
      checkout = "${config.home.homeDirectory}/code/private-agent-skills";
      targets = lib.listToAttrs (
        map (agent: {
          name = "${config.home.homeDirectory}/${agentAssets.skillTargets.${agent}}";
          value = builtins.attrNames (agentAssets.skillEntriesFor pkgs agent);
        }) agentAssets.agents
      );
    };

    # Only the helper and its configuration enter the store, never the checkout.
    home.activation.privateAgentSkills = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [[ -n "''${DRY_RUN_CMD:-}" ]]; then
        echo "Would sync and link private agent skills"
      elif [[ "''${SANDBOX:-0}" != 1 ]]; then
        ${syncCommand}/bin/private-skills-sync || \
          echo "Private skills sync incomplete; retry with just private-skills-sync" >&2
      fi
    '';
  };
}
