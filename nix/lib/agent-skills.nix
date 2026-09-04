{
  acpx-skills,
  agent-browser,
  anthropic-skills,
  containerAssets,
  cursor-plugins,
  lib,
  mattpocock-skills,
  ...
}:
let
  configRoot = containerAssets.config;
  skillsRoot = containerAssets.skills;
  agentInstructions = import ./agent-instructions.nix;
  codexCommandsRoot = configRoot + "/codex/commands";

  agents = [
    "claude"
    "codex"
    "pi"
  ];
  skillTargets = {
    claude = ".claude/skills";
    codex = ".codex/skills";
    pi = ".pi/agent/skills";
  };

  skillDirs =
    root:
    if builtins.pathExists root then
      lib.filterAttrs (name: type: type == "directory" && !(lib.hasPrefix "." name)) (
        builtins.readDir root
      )
    else
      { };
  discoveredSkills =
    root:
    lib.mapAttrs (name: _: {
      source = root + "/${name}";
    }) (skillDirs root);
  withAgents = selectedAgents: skill: skill // { agents = selectedAgents; };
  validateSkill =
    name: skill:
    assert lib.assertMsg (builtins.pathExists (
      skill.source + "/SKILL.md"
    )) "agent skill '${name}' is missing SKILL.md at ${toString skill.source}";
    skill;
  materializeSkill =
    pkgs: name: skill:
    skill
    // lib.optionalAttrs (skill ? patches) {
      source = pkgs.applyPatches {
        name = "agent-skill-${name}";
        src = skill.source;
        inherit (skill) patches;
      };
    };

  localSkillOverrides = {
    zmx.agents = [
      "claude"
      "codex"
    ];
    zmx-pi.agents = [ "pi" ];
  };
  localSharedSkills = lib.mapAttrs (name: skill: skill // (localSkillOverrides.${name} or { })) (
    discoveredSkills skillsRoot
  );
  codexSlashCommands = lib.mapAttrs (_: withAgents [ "codex" ]) (discoveredSkills codexCommandsRoot);
  externalSkills = {
    acpx.source = acpx-skills + "/skills/acpx";
    agent-browser.source = agent-browser + "/skills/agent-browser";
    domain-modeling.source = mattpocock-skills + "/skills/engineering/domain-modeling";
    frontend-design.source = anthropic-skills + "/skills/frontend-design";
    grill-with-docs.source = mattpocock-skills + "/skills/engineering/grill-with-docs";
    grilling.source = mattpocock-skills + "/skills/productivity/grilling";
    writing-for-agents.source = mattpocock-skills + "/skills/productivity/writing-for-agents";
    teach.source = mattpocock-skills + "/skills/productivity/teach";
    improve-codebase-architecture.source =
      mattpocock-skills + "/skills/engineering/improve-codebase-architecture";
    unslop = {
      source = cursor-plugins + "/pstack/skills/unslop";
      # Upstream disables automatic invocation despite declaring this skill must always apply.
      patches = [ ../patches/skills/unslop-enable-model-invocation.patch ];
    };
    wayfinder.source = mattpocock-skills + "/skills/engineering/wayfinder";
  };

  skillCatalog = lib.mapAttrs validateSkill (
    localSharedSkills // codexSlashCommands // externalSkills
  );

in
rec {
  inherit
    agents
    configRoot
    skillCatalog
    skillTargets
    ;

  codexFiles = {
    agents = builtins.toFile "codex-AGENTS.md" agentInstructions.codexGlobal;
    config =
      if builtins.pathExists (configRoot + "/codex/config.toml") then
        configRoot + "/codex/config.toml"
      else
        configRoot + "/codex/config.example.toml";
    hooks = configRoot + "/codex/hooks.json";
    hooksDir = configRoot + "/codex/hooks";
  };

  skillEntriesFor =
    pkgs: agent:
    lib.mapAttrs (materializeSkill pkgs) (
      lib.filterAttrs (_: skill: builtins.elem agent (skill.agents or agents)) skillCatalog
    );
  skillFiles =
    agent: skills:
    lib.mapAttrs' (
      name: skill:
      lib.nameValuePair "${skillTargets.${agent}}/${name}" {
        inherit (skill) source;
        force = true;
      }
    ) skills;
}
