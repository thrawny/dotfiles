{
  agent-browser,
  anthropic-skills,
  containerAssets,
  lib,
  mattpocock-skills,
  ...
}:
let
  configRoot = containerAssets.config;
  skillsRoot = containerAssets.skills;
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

  localSkillOverrides = {
    brave-search.agents = [ "pi" ];
  };
  localSharedSkills = lib.mapAttrs (name: skill: skill // (localSkillOverrides.${name} or { })) (
    discoveredSkills skillsRoot
  );
  codexSlashCommands = lib.mapAttrs (_: withAgents [ "codex" ]) (discoveredSkills codexCommandsRoot);
  externalSkills = {
    agent-browser.source = agent-browser + "/skills/agent-browser";
    frontend-design.source = anthropic-skills + "/skills/frontend-design";
    skill-creator.source = anthropic-skills + "/skills/skill-creator";
    teach.source = mattpocock-skills + "/skills/productivity/teach";
    grill-with-docs.source = mattpocock-skills + "/skills/engineering/grill-with-docs";
    improve-codebase-architecture.source =
      mattpocock-skills + "/skills/engineering/improve-codebase-architecture";
    tdd.source = mattpocock-skills + "/skills/engineering/tdd";
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
    agents = configRoot + "/codex/AGENTS-GLOBAL.md";
    config =
      if builtins.pathExists (configRoot + "/codex/config.toml") then
        configRoot + "/codex/config.toml"
      else
        configRoot + "/codex/config.example.toml";
    hooks = configRoot + "/codex/hooks.json";
  };

  skillEntriesFor =
    agent: lib.filterAttrs (_: skill: builtins.elem agent (skill.agents or agents)) skillCatalog;
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
