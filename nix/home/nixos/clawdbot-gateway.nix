{
  nix-clawdbot,
  config,
  ...
}:
let
  homeDir = config.home.homeDirectory;
in
{
  imports = [ nix-clawdbot.homeManagerModules.clawdbot ];

  programs.clawdbot = {
    enable = true;

    # Use Codex subscription (OAuth via ~/.codex/auth.json)
    defaults.model = "openai-codex/gpt-5.2-codex";

    # Disable macOS-only first-party plugins
    firstParty.peekaboo.enable = false;
    firstParty.summarize.enable = false;

    instances.default = {
      # Don't use providers.telegram - it generates old config format
      # Use configOverrides with new channels.telegram format instead
      configOverrides = {
        auth.profiles."openai-codex:default" = {
          provider = "openai-codex";
          mode = "oauth";
        };

        gateway.mode = "local";

        # Tailscale: expose gateway on tailnet
        tailscale.mode = "serve";
        gateway.auth.allowTailscale = true;

        # Telegram config (new format under channels)
        channels.telegram = {
          enabled = true;
          tokenFile = "${homeDir}/.secrets/telegram-token";
          allowFrom = [ 781443178 ];
        };
      };

      systemd.enable = true;
    };
  };
}
