{
  config,
  homeSource,
  lib,
  pkgs,
  ...
}@args:
let
  hmLib = lib.hm;
  containerAssets = args.containerAssets or null;
  dotfiles = args.dotfiles or null;
  excludedSharedSkills = args.excludedSharedSkills or [ ];
  enableCodexHooks = args.enableCodexHooks or true;
  enablePiExtensions = args.enablePiExtensions or true;
  repoBacked = homeSource == "repo";
  storeBacked = homeSource == "store";
  configPath =
    rel: if repoBacked then "${dotfiles}/config/${rel}" else containerAssets.config + "/${rel}";
  configSource =
    rel: if repoBacked then config.lib.file.mkOutOfStoreSymlink (configPath rel) else configPath rel;
  skillsRoot = if repoBacked then ../../../skills else containerAssets.skills;
  sharedSkillNames = lib.filter (name: !builtins.elem name excludedSharedSkills) (
    builtins.attrNames (
      lib.filterAttrs (name: type: type == "directory" && !(lib.hasPrefix "." name)) (
        builtins.readDir skillsRoot
      )
    )
  );
  linuxOnlySkills = [
    "wayvoice"
    "skill-eval"
  ];
  codexExcluded = linuxOnlySkills ++ [
    "brave-search"
    "skill-creator"
    "wayvoice"
  ];
  claudeExcluded = linuxOnlySkills ++ [
    "brave-search"
    "skill-creator"
  ];
  noLinuxOnly = lib.filter (name: !builtins.elem name linuxOnlySkills) sharedSkillNames;
  codexSharedSkillNames = lib.filter (name: !builtins.elem name codexExcluded) sharedSkillNames;
  claudeSharedSkillNames = lib.filter (name: !builtins.elem name claudeExcluded) sharedSkillNames;
  skillFiles =
    base: names:
    lib.listToAttrs (
      map (
        name:
        lib.nameValuePair "${base}/${name}" {
          source = skillsRoot + "/${name}";
        }
      ) names
    );

  seedExampleRepo =
    example: destination:
    hmLib.dag.entryBefore [ "linkGeneration" ] ''
      repo=${lib.escapeShellArg dotfiles}
      example_path="$repo/${example}"
      dest_path="$repo/${destination}"
      if [ ! -s "$dest_path" ] && [ -e "$example_path" ]; then
        install -Dm0644 "$example_path" "$dest_path"
      fi
    '';
  seedExampleStore =
    example: destination:
    hmLib.dag.entryBefore [ "linkGeneration" ] ''
      dest_path=${lib.escapeShellArg destination}
      if [ ! -s "$dest_path" ]; then
        install -Dm0644 ${lib.escapeShellArg (toString example)} "$dest_path"
      fi
    '';
in
{
  _module.args = {
    inherit
      linuxOnlySkills
      skillFiles
      ;
  };

  home = {
    sessionVariables = {
      CLAUDE_CONFIG_DIR = "${config.home.homeDirectory}/.claude";
    };

    activation = {
      seedClaudeJson = hmLib.dag.entryBefore [ "linkGeneration" ] ''
        claude_json="${config.home.homeDirectory}/.claude/.claude.json"
        install -d -m0755 "$(dirname "$claude_json")"
        if [ ! -s "$claude_json" ]; then
          printf '%s\n' '{"numStartups":1,"installMethod":"native","autoUpdates":false,"theme":"dark-daltonized","editorMode":"vim","hasCompletedOnboarding":true,"effortCalloutV2Dismissed":true}' > "$claude_json"
        fi
      '';
    }
    // lib.optionalAttrs repoBacked {
      seedCodexConfig = seedExampleRepo "config/codex/config.example.toml" "config/codex/config.toml";
      seedClaudeSettings = seedExampleRepo "config/claude/settings.example.json" "config/claude/settings.json";
      seedPiSettings = seedExampleRepo "config/pi/settings.example.json" "config/pi/settings.json";
    }
    // lib.optionalAttrs storeBacked {
      seedCodexConfig = seedExampleStore (configPath "codex/config.example.toml") "${config.home.homeDirectory}/.codex/config.toml";

      seedClaudeSettings = hmLib.dag.entryBefore [ "linkGeneration" ] ''
        dest_path=${lib.escapeShellArg "${config.home.homeDirectory}/.claude/settings.json"}
        if [ ! -s "$dest_path" ]; then
          install -d -m0755 "$(dirname "$dest_path")"
          ${pkgs.jq}/bin/jq '
            del(.hooks, .enabledPlugins)
            | .statusLine.command = "python3 ~/.claude/status_line.py"
          ' ${lib.escapeShellArg (toString (configPath "claude/settings.example.json"))} > "$dest_path"
          chmod 0644 "$dest_path"
        fi
      '';

      seedPiSettings = seedExampleStore (configPath "pi/settings.example.json") "${config.home.homeDirectory}/.pi/agent/settings.json";
    };

    file =
      skillFiles ".codex/skills" codexSharedSkillNames
      // skillFiles ".claude/skills" claudeSharedSkillNames
      // skillFiles ".pi/agent/skills" noLinuxOnly
      // lib.optionalAttrs enableCodexHooks {
        ".codex/hooks.json".source = configSource "codex/hooks.json";
      }
      // {
        ".codex/prompts".source = configSource "codex/prompts";
        ".codex/AGENTS.md".source = configSource "codex/AGENTS.md";

        ".pi/agent/models.json".source = configSource "pi/models.json";
        ".pi/agent/AGENTS.md".source = configSource "pi/AGENTS.md";
        ".pi/agent/prompts".source = configSource "pi/prompts";
        ".pi/agent/themes".source = configSource "pi/themes";

        ".claude/commands".source = configSource "claude/commands";
        ".claude/agents".source = configSource "claude/agents";
        ".claude/rules".source = configSource "claude/rules";
        ".claude/CLAUDE.md".source = configSource "claude/CLAUDE-GLOBAL.md";
        ".claude/.keep".text = "";
      }
      // lib.optionalAttrs enablePiExtensions {
        ".pi/agent/extensions".source = configSource "pi/extensions";
      }
      // lib.optionalAttrs repoBacked {
        ".codex/config.toml".source = configSource "codex/config.toml";
        ".pi/agent/settings.json".source = configSource "pi/settings.json";
        ".claude/settings.json".source = configSource "claude/settings.json";
      }
      // lib.optionalAttrs storeBacked {
        ".claude/status_line.py".source = configSource "claude/status_line.py";
      };
  };
}
