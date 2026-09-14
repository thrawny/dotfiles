#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
image_name=${MACOS_CONTAINER_IMAGE:-dotfiles-portable-macos-test}
container_engine=${CONTAINER_ENGINE:-docker}

"$container_engine" build \
  --file "$repo_root/docker/portable-macos.Dockerfile" \
  --target test \
  --tag "$image_name" \
  "$repo_root"

"$container_engine" run --rm "$image_name"
