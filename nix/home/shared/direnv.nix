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

      source_local_envrc() {
          if [[ -n "''${SANDBOX:-}" ]]; then
              source_env_if_exists .envrc.sandbox
          else
              source_env_if_exists .envrc.local
              dotenv_if_exists .secrets
          fi
      }

      use_docker() {
          local docker_vm docker_vm_ip docker_cache_dir docker_host_file

          docker_vm="''${SANDBOX_DOCKER_VM:-sandbox-docker}"
          docker_cache_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/sandbox/docker"
          docker_host_file="$docker_cache_dir/$docker_vm.host"

          if [[ -n "''${SANDBOX:-}" ]]; then
              if [[ ! -r "$docker_host_file" ]]; then
                  log_error "No cached address for Docker VM '$docker_vm'; load this direnv outside the sandbox first."
                  return 1
              fi
              docker_vm_ip="$(<"$docker_host_file")"
          else
              if ! has incus || ! has jq; then
                  log_error "use docker requires incus and jq."
                  return 1
              fi

              docker_vm_ip="$(
                  incus list "$docker_vm" --format=json 2>/dev/null \
                      | jq -r '.[0].state.network // {} | to_entries[] | select(.key != "lo" and .key != "docker0" and (.key | startswith("br-") | not) and (.key | startswith("veth") | not)) | .value.addresses[]? | select(.family == "inet") | .address' \
                      | head -n1
              )"
              if [[ -z "$docker_vm_ip" ]]; then
                  log_error "Docker VM '$docker_vm' is not running or has no IPv4 address."
                  return 1
              fi

              mkdir -p "$docker_cache_dir"
              printf '%s\n' "$docker_vm_ip" >"$docker_host_file"
          fi

          unset DOCKER_CONTEXT
          export DOCKER_HOST="tcp://$docker_vm_ip:2375"
          export DOCKER_CONFIG="$docker_cache_dir"
          export TESTCONTAINERS_HOST_OVERRIDE="$docker_vm_ip"
          mkdir -p "$DOCKER_CONFIG"
      }

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
