#!/usr/bin/env bash

[[ "${TRACE}" ]] && set -x
set -eou pipefail
shopt -s nullglob

main() {
    claude mcp add --transport http -s user context7 https://mcp.context7.com/mcp

}

main "$@"
