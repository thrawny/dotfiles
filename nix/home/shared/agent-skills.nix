{
  agent-browser,
  anthropic-skills,
  lib,
  mattpocock-skills,
  ...
}@args:
let
  containerAssets = args.containerAssets or null;
  skillsRoot = containerAssets.skills;
  codexCommandsRoot = containerAssets.config + "/codex/commands";

  agents = [
    "claude"
    "codex"
    "pi"
  ];
  targets = {
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
    grill-with-docs.source = mattpocock-skills + "/skills/engineering/grill-with-docs";
    improve-codebase-architecture.source =
      mattpocock-skills + "/skills/engineering/improve-codebase-architecture";
    tdd.source = mattpocock-skills + "/skills/engineering/tdd";
  };

  skillCatalog = lib.mapAttrs validateSkill (
    localSharedSkills // codexSlashCommands // externalSkills
  );
  skillEntriesFor =
    agent: lib.filterAttrs (_: skill: builtins.elem agent (skill.agents or agents)) skillCatalog;
  skillFiles =
    agent: skills:
    lib.mapAttrs' (
      name: skill:
      lib.nameValuePair "${targets.${agent}}/${name}" {
        inherit (skill) source;
        force = true;
      }
    ) skills;
in
{
  home.file =
    skillFiles "claude" (skillEntriesFor "claude")
    // skillFiles "codex" (skillEntriesFor "codex")
    // skillFiles "pi" (skillEntriesFor "pi");
}
