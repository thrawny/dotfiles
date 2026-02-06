#!/usr/bin/env bash
set -euo pipefail

# Deploy NixOS to a Hetzner server using nixos-anywhere
# Includes dotfiles in the deployment so Home Manager symlinks work on first boot

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
FLAKE_TARGET="${2:-thrawny-server}"
DOTFILES_REPO="https://github.com/thrawny/dotfiles.git"
USERNAME="thrawny"
TAILSCALE_AUTH_KEY=""
# Keep in sync with nix/hosts/attic-server/default.nix
ATTIC_S3_REGION="${ATTIC_S3_REGION:-hel1}"
ATTIC_S3_BUCKET="${ATTIC_S3_BUCKET:-thrawny-attic-storage}"
ATTIC_S3_ENDPOINT="${ATTIC_S3_ENDPOINT:-https://hel1.your-objectstorage.com}"

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
    echo "  $0 root@157.90.168.158 attic-server"
    exit 1
}

stage_tailscale_auth_key() {
    local key="$1"
    if [[ -z "$key" ]]; then
        return
    fi

    mkdir -p "$tmpdir/etc/tailscale"
    printf '%s\n' "$key" > "$tmpdir/etc/tailscale/auth-key"
    chmod 600 "$tmpdir/etc/tailscale/auth-key"
}

stage_attic_env_file() {
    local attic_access_key_id=""
    local attic_secret_access_key=""
    local token_rs256_secret_base64=""

    if ! command -v openssl >/dev/null 2>&1; then
        echo "Error: openssl is required to generate ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64"
        exit 1
    fi

    echo "==> Attic bootstrap (attic-server target)"
    echo "    Storage settings come from nix/hosts/attic-server/default.nix:"
    echo "    region=$ATTIC_S3_REGION bucket=$ATTIC_S3_BUCKET endpoint=$ATTIC_S3_ENDPOINT"
    read -rp "    Continue with these values? [Y/n] " confirm_storage
    if [[ "${confirm_storage:-Y}" =~ ^[Nn]$ ]]; then
        echo "Update nix/hosts/attic-server/default.nix storage settings, then rerun."
        exit 1
    fi

    while [[ -z "$attic_access_key_id" ]]; do
        read -rp "    S3 Access Key ID: " attic_access_key_id
    done

    while [[ -z "$attic_secret_access_key" ]]; do
        read -rsp "    S3 Secret Access Key: " attic_secret_access_key
        echo ""
    done

    token_rs256_secret_base64="$(openssl genrsa -traditional 4096 | openssl base64 -A)"

    mkdir -p "$tmpdir/etc/atticd"
    cat > "$tmpdir/etc/atticd/atticd.env" <<EOF
ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=$token_rs256_secret_base64
AWS_ACCESS_KEY_ID=$attic_access_key_id
AWS_SECRET_ACCESS_KEY=$attic_secret_access_key
EOF
    chmod 600 "$tmpdir/etc/atticd/atticd.env"
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

if [[ "$FLAKE_TARGET" == "attic-server" ]]; then
    echo ""
    echo "==> Tailscale auth key (optional, used on first boot)"
    echo "    Generate at: https://login.tailscale.com/admin/settings/keys"
    read -rsp "    Paste Tailscale auth key (leave empty to skip): " TAILSCALE_AUTH_KEY
    echo ""
    stage_tailscale_auth_key "$TAILSCALE_AUTH_KEY"
    stage_attic_env_file
fi

# Deploy
# Using UID:GID (1000:100) since username doesn't exist yet during install
echo "==> Running nixos-anywhere..."
nix run github:nix-community/nixos-anywhere -- \
    --build-on local \
    --flake "$REPO_ROOT/nix#$FLAKE_TARGET" \
    --extra-files "$tmpdir" \
    --chown "/home/$USERNAME/dotfiles" "1000:100" \
    "$TARGET_HOST"

if [[ "$FLAKE_TARGET" == "attic-server" ]]; then
    if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
        echo ""
        echo "==> Tailscale auth key provisioned to /etc/tailscale/auth-key"
        echo "    On first boot, systemd service tailscale-autoconnect will run tailscale up."
    else
        echo ""
        echo "==> Tailscale auth key was not provided"
        echo "    Run on server later: sudo tailscale up --auth-key <key>"
    fi
else
    # Bootstrap Tailscale for non-attic hosts
    echo ""
    echo "==> Generate a one-off auth key at: https://login.tailscale.com/admin/settings/keys"
    read -rp "Paste Tailscale auth key: " TAILSCALE_AUTH_KEY

    if [[ -n "$TAILSCALE_AUTH_KEY" ]]; then
        echo "==> Authenticating Tailscale..."
        ssh -o StrictHostKeyChecking=accept-new "$USERNAME@$HOST_IP" \
            "sudo tailscale up --auth-key '$TAILSCALE_AUTH_KEY'"
        echo "==> Tailscale connected"
    else
        echo "==> Skipping Tailscale (no key provided)"
    fi
fi

echo ""
echo "=== Deployment complete ==="
echo "SSH in with: ssh $USERNAME@${TARGET_HOST#*@}"
