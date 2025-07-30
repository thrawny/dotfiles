#!/usr/bin/env bash

[[ "${TRACE}" ]] && set -x
set -eou pipefail
shopt -s nullglob

main() {
    claude mcp add --transport sse context7 https://mcp.context7.com/sse
    claude mcp add -s user playwright npx @playwright/mcp@latest -- --caps vision
}

main "$@"
