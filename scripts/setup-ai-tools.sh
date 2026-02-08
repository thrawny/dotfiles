#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <target-host>"
    echo ""
    echo "Install/update Claude Code and Codex CLI on a remote host,"
    echo "then upload credentials from the local machine."
    echo ""
    echo "Example:"
    echo "  $0 thrawny-server"
    exit 1
}

[[ $# -lt 1 ]] && usage
TARGET="$1"

echo "==> Installing Claude Code on ${TARGET}..."
ssh "$TARGET" "curl -fsSL https://claude.ai/install.sh | bash"

echo "==> Installing/updating Codex CLI on ${TARGET}..."
ssh "$TARGET" "pnpm install -g @openai/codex"

echo "==> Uploading credentials to ${TARGET}..."
ssh "$TARGET" "mkdir -p ~/.claude ~/.codex"
scp ~/.claude/.credentials.json "${TARGET}:~/.claude/.credentials.json"
scp ~/.codex/auth.json "${TARGET}:~/.codex/auth.json"
ssh "$TARGET" "chmod 600 ~/.claude/.credentials.json ~/.codex/auth.json"

echo "==> Done. Verify with: ssh ${TARGET} 'claude --version && codex --version'"
