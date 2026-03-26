{
  config,
  configSource,
  dotfiles,
  lib,
  ...
}:
let
  hmLib = lib.hm;
  seedExample =
    example: destination:
    hmLib.dag.entryBefore [ "linkGeneration" ] ''
      repo=${lib.escapeShellArg dotfiles}
      example_path="$repo/${example}"
      dest_path="$repo/${destination}"
      if [ ! -s "$dest_path" ] && [ -e "$example_path" ]; then
        install -Dm0644 "$example_path" "$dest_path"
      fi
    '';
in
{
  home = {
    sessionPath = [ "${config.home.homeDirectory}/dotfiles/bin" ];

    activation = {
      seedCodexConfig = seedExample "config/codex/config.example.toml" "config/codex/config.toml";
      seedClaudeSettings = seedExample "config/claude/settings.example.json" "config/claude/settings.json";
      seedPiSettings = seedExample "config/pi/settings.example.json" "config/pi/settings.json";

    };

    file = {
      ".codex/config.toml".source = configSource "codex/config.toml";
      ".pi/agent/settings.json".source = configSource "pi/settings.json";
      ".claude/settings.json".source = configSource "claude/settings.json";
    };
  };
}
