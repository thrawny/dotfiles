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

    instances.default = {
      providers.telegram = {
        enable = true;
        botTokenFile = "${homeDir}/.secrets/telegram-token";
        allowFrom = [ 781443178 ];
      };

      configOverrides = {
        auth.profiles."openai-codex:default" = {
          provider = "openai-codex";
          mode = "oauth";
        };

        gateway.mode = "local";

        # Tailscale: expose gateway on tailnet
        tailscale.mode = "serve";
        gateway.auth.allowTailscale = true;
      };

      systemd.enable = true;
    };
  };
}
