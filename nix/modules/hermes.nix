{
  lib,
  pkgs,
}:
let
  yaml = pkgs.formats.yaml { };
  home = "/srv/agents/hermes/home";
  workspace = "/srv/agents/hermes/workspace";
  envFile = "${home}/.hermes/.env";

  discordPluginManifest = ''
    name: discord
    version: bundled
    description: Register the bundled Discord platform adapter.
    kind: platform
  '';

  discordPluginInit = ''
    from plugins.platforms.discord.adapter import register
  '';

  hermesConfig = {
    plugins.enabled = [ "discord" ];

    model = {
      provider = "openai-codex";
      default = "gpt-5.6-sol";
    };

    agent.reasoning_effort = "low";

    terminal = {
      backend = "local";
      working_dir = workspace;
    };

    discord = {
      require_mention = true;
      thread_require_mention = false;
      auto_thread = true;
      reactions = true;
      allowed_channels = [
        "777231848123924561"
        "1510629338264113252"
        "1512036755673448579"
      ];
      free_response_channels = [ "1512036755673448579" ];
      history_backfill = true;
      history_backfill_limit = 50;
      allow_mentions = {
        everyone = false;
        roles = false;
        users = true;
        replied_user = true;
      };
    };
  };

  hermesConfigFile = yaml.generate "hermes-config.yaml" hermesConfig;
in
{
  inherit home workspace envFile;

  prepareConfig = pkgs.writeShellApplication {
    name = "hermes-prepare-config";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail

      hermes_home=${lib.escapeShellArg home}
      config_path="$hermes_home/.hermes/config.yaml"
      env_path=${lib.escapeShellArg envFile}
      discord_plugin_dir="$hermes_home/.hermes/plugins/discord"

      install -d -m 0750 -o hermes -g hermes "$hermes_home/.hermes"
      install -m 0600 -o hermes -g hermes ${hermesConfigFile} "$config_path"
      install -d -m 0750 -o hermes -g hermes "$discord_plugin_dir"
      install -m 0644 -o hermes -g hermes ${pkgs.writeText "hermes-discord-plugin.yaml" discordPluginManifest} "$discord_plugin_dir/plugin.yaml"
      install -m 0644 -o hermes -g hermes ${pkgs.writeText "hermes-discord-plugin.py" discordPluginInit} "$discord_plugin_dir/__init__.py"

      if [ ! -e "$env_path" ]; then
        install -m 0600 -o hermes -g hermes /dev/null "$env_path"
      fi

      ensure_env_var() {
        key="$1"
        value="$2"
        if ! grep -q "^$key=" "$env_path"; then
          printf '%s=%s\n' "$key" "$value" >> "$env_path"
        fi
      }

      set_env_var() {
        key="$1"
        value="$2"
        tmp="$(mktemp)"
        grep -v "^$key=" "$env_path" > "$tmp" || true
        printf '%s=%s\n' "$key" "$value" >> "$tmp"
        install -m 0600 -o hermes -g hermes "$tmp" "$env_path"
        rm -f "$tmp"
      }

      ensure_env_var DISCORD_ALLOWED_USERS 231780291440672768
      set_env_var DISCORD_ALLOWED_CHANNELS 777231848123924561,1510629338264113252,1512036755673448579
      set_env_var DISCORD_FREE_RESPONSE_CHANNELS 1512036755673448579
      set_env_var DISCORD_ALLOW_ALL_USERS false
      set_env_var DISCORD_REQUIRE_MENTION true
      set_env_var DISCORD_THREAD_REQUIRE_MENTION false

      chown hermes:hermes "$env_path"
      chmod 0600 "$env_path"
    '';
  };
}
