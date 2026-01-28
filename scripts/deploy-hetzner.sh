#!/usr/bin/env bash
set -euo pipefail

# Deploy NixOS to a Hetzner server using nixos-anywhere
# Includes dotfiles in the deployment so Home Manager symlinks work on first boot

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
FLAKE_TARGET="${2:-thrawny-server}"
DOTFILES_REPO="https://github.com/thrawny/dotfiles.git"
USERNAME="thrawny"

usage() {
    echo "Usage: $0 <target-host> [flake-target]"
    echo ""
    echo "Arguments:"
    echo "  target-host   SSH target (e.g., root@157.90.168.158)"
    echo "  flake-target  NixOS flake target (default: thrawny-server)"
    echo ""
    echo "Example:"
    echo "  $0 root@157.90.168.158"
    echo "  $0 root@157.90.168.158 thrawny-server"
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

TARGET_HOST="$1"

echo "=== Hetzner NixOS Deployment ==="
echo "Target: $TARGET_HOST"
echo "Flake:  $REPO_ROOT/nix#$FLAKE_TARGET"
echo ""

# Remove old host key (server gets new keys after reinstall)
HOST_IP="${TARGET_HOST#*@}"
echo "==> Removing old SSH host key for $HOST_IP..."
ssh-keygen -R "$HOST_IP" 2>/dev/null || true

# Create temp directory for extra files
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Clone dotfiles
echo "==> Cloning dotfiles..."
git clone --depth 1 "$DOTFILES_REPO" "$tmpdir/home/$USERNAME/dotfiles"

# Deploy
# Using UID:GID (1000:100) since username doesn't exist yet during install
echo "==> Running nixos-anywhere..."
nix run github:nix-community/nixos-anywhere -- \
    --flake "$REPO_ROOT/nix#$FLAKE_TARGET" \
    --extra-files "$tmpdir" \
    --chown "/home/$USERNAME/dotfiles" "1000:100" \
    "$TARGET_HOST"

echo ""
echo "=== Deployment complete ==="
echo "SSH in with: ssh $USERNAME@${TARGET_HOST#*@}"
