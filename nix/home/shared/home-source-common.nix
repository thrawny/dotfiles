{
  configSource,
  lib,
  ...
}@args:
let
  enableCodexHooks = args.enableCodexHooks or true;
  enablePiExtensions = args.enablePiExtensions or true;
in
{
  home = {
    sessionPath = [
      "$HOME/.cargo/bin"
      "$HOME/.npm-global/bin"
      "$HOME/.local/share/pnpm"
      "$HOME/.local/bin"
      "$HOME/go/bin"
    ];

    file =
      lib.optionalAttrs enableCodexHooks {
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
      };
  };
}
