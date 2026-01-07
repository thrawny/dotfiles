#!/usr/bin/env bash
set -euo pipefail

# Install Nix in constrained container environments
#
# This script works around the "cannot get exit status of PID: No child processes"
# error that occurs with both Determinate Systems and official NixOS installers
# in certain container environments (e.g., Claude Code containers).
#
# It downloads the official Nix tarball and manually sets up profiles.
#
# Usage: ./install-nix-container.sh

NIX_VERSION="${NIX_VERSION:-2.33.0}"
ARCH=$(uname -m)

echo "=== Nix Container Installer ==="
echo "Version: $NIX_VERSION"
echo "Architecture: $ARCH"
echo ""

# Check if already installed
if command -v nix &>/dev/null; then
    echo "Nix is already installed:"
    nix --version
    exit 0
fi

# Require root for system-wide installation
if [[ $EUID -ne 0 ]]; then
    echo "This script requires root to create /nix and build users."
    echo "Run with sudo or as root."
    exit 1
fi

# Create nixbld group and users if they don't exist
echo "==> Creating nixbld group and users..."
if ! getent group nixbld >/dev/null 2>&1; then
    groupadd -g 30000 nixbld
fi

for n in $(seq 1 32); do
    if ! id "nixbld$n" >/dev/null 2>&1; then
        useradd -c "Nix build user $n" -d /var/empty -g nixbld -G nixbld -M -N -r -s "$(which nologin)" "nixbld$n" 2>/dev/null || true
    fi
done

# Create /nix directory
echo "==> Creating /nix directory..."
mkdir -p /nix
chown root:nixbld /nix
chmod 1775 /nix

# Download and extract Nix
echo "==> Downloading Nix $NIX_VERSION..."
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

URL="https://releases.nixos.org/nix/nix-${NIX_VERSION}/nix-${NIX_VERSION}-${ARCH}-linux.tar.xz"
curl -fsSL "$URL" -o "$TMPDIR/nix.tar.xz"

echo "==> Extracting Nix..."
cd "$TMPDIR"
tar -xf nix.tar.xz

# Copy store paths
echo "==> Copying Nix store..."
UNPACK_DIR="$TMPDIR/nix-${NIX_VERSION}-${ARCH}-linux"
if [[ -d "$UNPACK_DIR/store" ]]; then
    cp -a "$UNPACK_DIR/store/"* /nix/store/
fi

# Find the nix package in store
NIX_STORE_PATH=$(find /nix/store -maxdepth 1 -name "*-nix-${NIX_VERSION}" -type d | head -1)
if [[ -z "$NIX_STORE_PATH" ]]; then
    echo "Error: Could not find nix package in store"
    exit 1
fi

echo "==> Found Nix at: $NIX_STORE_PATH"

# Create profile directories
echo "==> Setting up profiles..."
mkdir -p /nix/var/nix/profiles/per-user/root
mkdir -p /nix/var/nix/db
mkdir -p /nix/var/nix/gcroots
mkdir -p /nix/var/nix/temproots

# Link the default profile
ln -sfn "$NIX_STORE_PATH" /nix/var/nix/profiles/default

# Create root user profile link
rm -rf /root/.nix-profile
ln -sfn /nix/var/nix/profiles/default /root/.nix-profile

# Create global nix config
echo "==> Configuring Nix..."
mkdir -p /etc/nix
cat > /etc/nix/nix.conf << 'EOF'
experimental-features = nix-command flakes
sandbox = false
build-users-group = nixbld
EOF

# Create user config directory
mkdir -p /root/.config/nix
cat > /root/.config/nix/nix.conf << 'EOF'
experimental-features = nix-command flakes
sandbox = false
EOF

# Add to PATH in profile.d (for login shells)
echo "==> Adding Nix to PATH..."
mkdir -p /etc/profile.d
cat > /etc/profile.d/nix.sh << 'EOF'
# Nix environment setup
if [ -d /nix/var/nix/profiles/default/bin ]; then
    export PATH="/nix/var/nix/profiles/default/bin:$PATH"
fi
EOF

# Create symlinks in /usr/local/bin for non-login shells
echo "==> Creating symlinks in /usr/local/bin..."
mkdir -p /usr/local/bin
for cmd in /nix/var/nix/profiles/default/bin/*; do
    if [[ -x "$cmd" ]]; then
        ln -sfn "$cmd" "/usr/local/bin/$(basename "$cmd")"
    fi
done

# Also add for current session
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# Verify installation
echo ""
echo "==> Verifying installation..."
if nix --version; then
    echo ""
    echo "=== Nix installed successfully! ==="
    echo ""
    echo "Nix commands are now available in /usr/local/bin."
    echo ""
    echo "Test with:"
    echo "  nix eval --raw nixpkgs#hello.name"
else
    echo "Error: Nix installation verification failed"
    exit 1
fi
