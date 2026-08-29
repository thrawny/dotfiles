{
  config,
  homeSource,
  lib,
  pkgs,
  theme,
  themeLib,
  ...
}@args:
let
  hmLib = lib.hm;
  containerAssets = args.containerAssets or null;
  dotfiles = args.dotfiles or null;
  enableAgentSwitchIntegration = config.dotfiles.agentSwitch.enable;
  repoBacked = homeSource == "repo";
  storeBacked = homeSource == "store";
  configPath =
    rel: if repoBacked then "${dotfiles}/config/${rel}" else containerAssets.config + "/${rel}";
  configSource =
    rel: if repoBacked then config.lib.file.mkOutOfStoreSymlink (configPath rel) else configPath rel;
  rulesRoot = if repoBacked then ../../../rules else containerAssets.rules;
  rulesSource =
    if repoBacked then config.lib.file.mkOutOfStoreSymlink (toString rulesRoot) else rulesRoot;
  instructionBlockOption =
    description:
    lib.mkOption {
      type = lib.types.bool;
      default = true;
      inherit description;
    };
  instructionConfig = config.dotfiles.agentInstructions;
  agentInstructionLib = import ../../lib/agent-instructions.nix;
  agentInstructions = agentInstructionLib.mkInstructions {
    enableGrilling = instructionConfig.grilling.enable;
    enableEphemeralTools = instructionConfig.ephemeralTools.enable;
    enableShellPortability = instructionConfig.shellPortability.enable;
    enableSandbox = instructionConfig.sandbox.enable;
    enableBackgroundTasks = instructionConfig.backgroundTasks.enable;
    enableContextManagement = instructionConfig.contextManagement.enable;
    enableCodeQuality = instructionConfig.codeQuality.enable;
    enablePiWorkflow = instructionConfig.piWorkflow.enable;
  };
  stripAgentSwitchHooks = ''
    if .hooks then
      .hooks |= with_entries(
        .value |= map(
          .hooks |= map(select(((.command // "") | contains("agent-switch")) | not))
          | select((.hooks | length) > 0)
        )
        | select((.value | length) > 0)
      )
    else
      .
    end
  '';
  claudeSettingsFilter = if enableAgentSwitchIntegration then "." else stripAgentSwitchHooks;

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
  seedClaudeSettingsRepo = hmLib.dag.entryBefore [ "linkGeneration" ] ''
    repo=${lib.escapeShellArg dotfiles}
    example_path="$repo/config/claude/settings.example.json"
    dest_path="$repo/config/claude/settings.json"
    if [ ! -s "$dest_path" ] && [ -e "$example_path" ]; then
      install -d -m0755 "$(dirname "$dest_path")"
      ${pkgs.jq}/bin/jq ${lib.escapeShellArg claudeSettingsFilter} "$example_path" > "$dest_path"
      chmod 0644 "$dest_path"
    fi
  '';
  seedClaudeLocalInstructionsRepo = hmLib.dag.entryBefore [ "linkGeneration" ] ''
    local_instructions=${lib.escapeShellArg "${dotfiles}/config/claude/CLAUDE.local.md"}
    if [ ! -e "$local_instructions" ]; then
      install -Dm0644 /dev/null "$local_instructions"
    fi
  '';
in
{
  options.dotfiles = {
    agentSwitch.enable = lib.mkEnableOption "agent-switch integrations for AI tools";

    agentInstructions = {
      grilling.enable = instructionBlockOption "Include Claude grilling instructions";
      ephemeralTools.enable = instructionBlockOption "Include ephemeral tool instructions";
      shellPortability.enable = instructionBlockOption "Include shell portability instructions";
      sandbox.enable = instructionBlockOption "Include sandbox-specific instructions";
      backgroundTasks.enable = instructionBlockOption "Include background task instructions";
      contextManagement.enable = instructionBlockOption "Include context management instructions";
      codeQuality.enable = instructionBlockOption "Include Codex code quality instructions";
      piWorkflow.enable = instructionBlockOption "Include Pi workflow instructions";
    };
  };

  config.home = {
    sessionVariables = {
      CLAUDE_CONFIG_DIR = "${config.home.homeDirectory}/.claude";
    };

    activation = {
      seedClaudeJson = hmLib.dag.entryBefore [ "linkGeneration" ] ''
        claude_json="${config.home.homeDirectory}/.claude/.claude.json"
        install -d -m0755 "$(dirname "$claude_json")"
        if [ ! -s "$claude_json" ]; then
          printf '%s\n' '{"numStartups":1,"installMethod":"native","autoUpdates":false,"theme":"dark-daltonized","hasCompletedOnboarding":true,"effortCalloutV2Dismissed":true}' > "$claude_json"
        fi
      '';
    }
    // lib.optionalAttrs repoBacked {
      seedCodexConfig = seedExampleRepo "config/codex/config.example.toml" "config/codex/config.toml";
      seedClaudeSettings = seedClaudeSettingsRepo;
      seedClaudeLocalInstructions = seedClaudeLocalInstructionsRepo;
      seedPiSettings = seedExampleRepo "config/pi/settings.example.json" "config/pi/settings.json";
    }
    // lib.optionalAttrs storeBacked {
      seedCodexConfig = seedExampleStore (configPath "codex/config.example.toml") "${config.home.homeDirectory}/.codex/config.toml";

      seedClaudeSettings = hmLib.dag.entryBefore [ "linkGeneration" ] ''
        dest_path=${lib.escapeShellArg "${config.home.homeDirectory}/.claude/settings.json"}
        if [ -L "$dest_path" ]; then
          rm "$dest_path"
        fi
        if [ ! -s "$dest_path" ]; then
          install -d -m0755 "$(dirname "$dest_path")"
          ${pkgs.jq}/bin/jq ${lib.escapeShellArg ''
            ${claudeSettingsFilter}
            | del(.enabledPlugins)
            | .statusLine.command = "python3 ~/.claude/status_line.py"
          ''} ${lib.escapeShellArg (toString (configPath "claude/settings.example.json"))} > "$dest_path"
          chmod 0644 "$dest_path"
        fi
      '';

      seedPiSettings = seedExampleStore (configPath "pi/settings.example.json") "${config.home.homeDirectory}/.pi/agent/settings.json";
    };

    file = {
      ".codex/hooks.json".source = configSource (
        if enableAgentSwitchIntegration then "codex/hooks.agent-switch.json" else "codex/hooks.json"
      );
      ".codex/hooks".source = configSource "codex/hooks";

      ".codex/AGENTS.md".text = agentInstructions.codexGlobal;

      ".pi/agent/AGENTS.md".text = agentInstructions.piGlobal;
      ".pi/agent/rules".source = rulesSource;
      ".pi/agent/prompts".source = configSource "pi/prompts";
      # Pi themes have no inheritance mechanism, so the complete document is
      # generated from the central theme (edit nix/themes/monokai.json).
      ".pi/agent/themes/monokai-pi.json".text = builtins.toJSON (themeLib.piTheme theme);
      ".pi/agent/claude-bridge.json".source = configSource "pi/claude-bridge.json";
      ".pi/agent/openai-server-compaction.json".source = configSource "pi/openai-server-compaction.json";
      ".pi/agent/pi-diff.json".source = configSource "pi/pi-diff.json";
      ".pi/agent/pi-vcc-config.json".source = configSource "pi/pi-vcc-config.json";
      ".pi/agent/models.json".source = configSource "pi/models.json";
      ".pi/agent/keybindings.json".source = configSource "pi/keybindings.json";
      ".pi/agent/extensions".source = configSource "pi/extensions";

      ".claude/commands".source = configSource "claude/commands";
      ".claude/agents".source = configSource "claude/agents";
      ".claude/rules".source = rulesSource;
      ".claude/CLAUDE.md".text =
        agentInstructions.claudeGlobal
        + lib.optionalString repoBacked ''

          @~/.claude/CLAUDE.local.md
        '';
      ".claude/.keep".text = "";
    }
    // lib.optionalAttrs repoBacked {
      ".codex/config.toml".source = configSource "codex/config.toml";
      ".pi/agent/settings.json".source = configSource "pi/settings.json";
      ".claude/settings.json".source = configSource "claude/settings.json";
      ".claude/CLAUDE.local.md".source = configSource "claude/CLAUDE.local.md";
    }
    // lib.optionalAttrs storeBacked {
      ".claude/status_line.py".source = configSource "claude/status_line.py";
    };
  };
}
