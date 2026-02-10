#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <target-host>"
    echo ""
    echo "Upload Claude/Codex/Pi auth files to a remote host."
    echo ""
    echo "Example:"
    echo "  $0 thrawny-server"
    exit 1
}

[[ $# -lt 1 ]] && usage
TARGET="$1"

CLAUDE_AUTH="${HOME}/.claude/.credentials.json"
CODEX_AUTH="${HOME}/.codex/auth.json"
PI_AUTH="${HOME}/.pi/agent/auth.json"

echo "==> Preparing auth directories on ${TARGET}..."
ssh "$TARGET" "mkdir -p ~/.claude ~/.codex ~/.pi/agent"

uploaded=()

if [[ -f "${CLAUDE_AUTH}" ]]; then
    echo "==> Uploading Claude auth..."
    scp "${CLAUDE_AUTH}" "${TARGET}:~/.claude/.credentials.json"
    uploaded+=("~/.claude/.credentials.json")
else
    echo "==> Skipping Claude auth (missing: ${CLAUDE_AUTH})"
fi

if [[ -f "${CODEX_AUTH}" ]]; then
    echo "==> Uploading Codex auth..."
    scp "${CODEX_AUTH}" "${TARGET}:~/.codex/auth.json"
    uploaded+=("~/.codex/auth.json")
else
    echo "==> Skipping Codex auth (missing: ${CODEX_AUTH})"
fi

if [[ -f "${PI_AUTH}" ]]; then
    echo "==> Uploading Pi auth..."
    scp "${PI_AUTH}" "${TARGET}:~/.pi/agent/auth.json"
    uploaded+=("~/.pi/agent/auth.json")
else
    echo "==> Skipping Pi auth (missing: ${PI_AUTH})"
fi

if [[ ${#uploaded[@]} -gt 0 ]]; then
    echo "==> Fixing auth file permissions on ${TARGET}..."
    ssh "$TARGET" "chmod 600 ${uploaded[*]}"
    echo "==> Done. Synced: ${uploaded[*]}"
else
    echo "==> Nothing uploaded (no local auth files found)."
fi
