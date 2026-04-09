{
  config,
  homeSource,
  lib,
  ...
}:
let
  repoBacked = homeSource == "repo";
in
{
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    config.whitelist.prefix =
      lib.optionals repoBacked [
        "${config.home.homeDirectory}/dotfiles"
      ]
      ++ [
        "${config.home.homeDirectory}/code"
        "${config.home.homeDirectory}/work"
      ];
    stdlib = ''
      dotenv_if_exists .env
      dotenv_if_exists .env.local
      source_env_if_exists .envrc.local
      dotenv_if_exists .secrets

      use_zmx() {
          local project_name dir_name

          if git rev-parse --git-common-dir &>/dev/null 2>&1; then
              local git_common_dir git_dir
              git_common_dir="$(realpath "$(git rev-parse --git-common-dir)")"
              git_dir="$(realpath "$(git rev-parse --git-dir)")"

              project_name="$(basename "$(dirname "$git_common_dir")")"

              if [[ "$git_dir" != "$git_common_dir" ]]; then
                  local worktree_name
                  worktree_name="$(basename "$(git rev-parse --show-toplevel)")"
                  dir_name="''${project_name}-''${worktree_name}"
              else
                  dir_name="$project_name"
              fi
          else
              dir_name="$(basename "$PWD")"
          fi

          local zmx_dir="$HOME/.cache/zmx/$dir_name"
          mkdir -p "$zmx_dir"
          export ZMX_DIR="$zmx_dir"
      }

      layout_uv() {
          if [[ -d ".venv" ]]; then
              VIRTUAL_ENV="$(pwd)/.venv"
          fi

          if [[ -z $VIRTUAL_ENV || ! -d $VIRTUAL_ENV ]]; then
              if [[ ! -f pyproject.toml ]]; then
                  log_status "No uv project exists. Executing \`uv init\` to create one."
                  uv init
              fi
              uv venv
              VIRTUAL_ENV="$(pwd)/.venv"
          fi

          PATH_add "$VIRTUAL_ENV/bin"
          export UV_ACTIVE=1
          export VIRTUAL_ENV
      }
    '';
  };
}
