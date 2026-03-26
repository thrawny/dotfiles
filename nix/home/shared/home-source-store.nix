{
  config,
  configPath,
  configSource,
  lib,
  pkgs,
  ...
}:
let
  hmLib = lib.hm;
  seedExample =
    example: destination:
    hmLib.dag.entryBefore [ "linkGeneration" ] ''
      dest_path=${lib.escapeShellArg destination}
      if [ ! -s "$dest_path" ]; then
        install -Dm0644 ${lib.escapeShellArg (toString example)} "$dest_path"
      fi
    '';
in
{
  home = {
    activation = {
      seedCodexConfig = seedExample (configPath "codex/config.example.toml") "${config.home.homeDirectory}/.codex/config.toml";

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

      seedPiSettings = seedExample (configPath "pi/settings.example.json") "${config.home.homeDirectory}/.pi/agent/settings.json";
    };

    file = {
      ".claude/status_line.py".source = configSource "claude/status_line.py";
    };
  };
}
