{
  config,
  configPath,
  homeSource,
  dotfiles,
  lib,
  pkgs,
  username,
  ...
}:
{
  imports = [
    ../shared/home-base.nix
    ../shared/ai-tools.nix
    ../shared/packages.nix
    ../shared/btop.nix
    ../shared/direnv.nix
    ../shared/git.nix
    ../shared/k9s.nix
    ../shared/lazygit.nix
    ../shared/npm.nix
    ../shared/nvim.nix
    ../shared/starship.nix
    ../shared/zsh.nix
    ../shared/zmx.nix
  ];

  _module.args = {
    enableCodexHooks = false;
    enablePiExtensions = false;
  };

  programs.home-manager.enable = true;

  home = {
    inherit username;
    homeDirectory = "/home/${username}";

    packages = with pkgs; [
      ncurses
      (lib.hiPrio ghostty.terminfo)
    ];

    sessionVariables = {
      NVIM_HEADLESS = "1";
      COLORTERM = "truecolor";
    }
    // lib.optionalAttrs (homeSource == "store") {
      NVIM_STORE_CONFIG = "1";
    };

    activation = {
      seedCodexConfig = lib.mkForce (
        lib.hm.dag.entryBefore [ "linkGeneration" ] ''
          if [ "${homeSource}" = "repo" ]; then
            dest_path=${lib.escapeShellArg "${dotfiles}/config/codex/config.toml"}
            example_path=${lib.escapeShellArg "${dotfiles}/config/codex/config.example.toml"}
          else
            dest_path=${lib.escapeShellArg "${config.home.homeDirectory}/.codex/config.toml"}
            example_path=${lib.escapeShellArg "${configPath "codex/config.example.toml"}"}
          fi

          if [ ! -s "$dest_path" ] && [ -e "$example_path" ]; then
            install -d -m0755 "$(dirname "$dest_path")"
            sed \
              -e 's/^voice_transcription = true$/voice_transcription = false/' \
              -e 's/^multi_agent = true$/multi_agent = false/' \
              -e 's/^codex_hooks = true$/codex_hooks = false/' \
              "$example_path" > "$dest_path"
            chmod 0644 "$dest_path"
          fi
        ''
      );

      seedClaudeSettings = lib.mkForce (
        lib.hm.dag.entryBefore [ "linkGeneration" ] ''
          if [ "${homeSource}" = "repo" ]; then
            dest_path=${lib.escapeShellArg "${dotfiles}/config/claude/settings.json"}
            example_path=${lib.escapeShellArg "${dotfiles}/config/claude/settings.example.json"}
          else
            dest_path=${lib.escapeShellArg "${config.home.homeDirectory}/.claude/settings.json"}
            example_path=${lib.escapeShellArg "${configPath "claude/settings.example.json"}"}
          fi

          if [ ! -s "$dest_path" ] && [ -e "$example_path" ]; then
            install -d -m0755 "$(dirname "$dest_path")"
            if [ "${homeSource}" = "repo" ]; then
              ${pkgs.jq}/bin/jq 'del(.hooks)' "$example_path" > "$dest_path"
            else
              ${pkgs.jq}/bin/jq 'del(.hooks) | .statusLine.command = "python3 ~/.claude/status_line.py"' "$example_path" > "$dest_path"
            fi
            chmod 0644 "$dest_path"
          fi
        ''
      );
    };
  };
}
