#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script for Fedora Asahi Linux on MacBook Air
# Sets up niri + DankMaterialShell desktop with dotfiles

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
HOME_MANAGER_FLAKE="thrawny-asahi-air"

echo "=== Asahi Fedora Bootstrap ==="
echo "Dotfiles: $DOTFILES_DIR"
echo ""

if [[ ! -d "$DOTFILES_DIR" ]]; then
    echo "Error: dotfiles not found at $DOTFILES_DIR"
    echo "Clone first: git clone <repo> $DOTFILES_DIR"
    exit 1
fi

# --- SELinux ---
echo "==> Disabling SELinux..."
if [[ -f /etc/selinux/config ]]; then
    sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
fi

# --- Console font ---
echo "==> Setting larger console font..."
echo 'FONT=latarcyrheb-sun32' | sudo tee /etc/vconsole.conf > /dev/null

# --- DNF COPR Repos ---
echo "==> Enabling COPR repos..."
sudo dnf copr enable -y fmonteghetti/keyd
sudo dnf copr enable -y avenge/dms

# --- DNF Update ---
echo "==> Updating system packages..."
sudo dnf update -y

# --- DNF Packages ---
echo "==> Installing DNF packages..."
sudo dnf install -y \
    niri \
    ghostty \
    playerctl \
    wireplumber \
    xwayland-satellite \
    keyd \
    dms \
    cascadia-fonts-all \
    flatpak \
    greetd \
    greetd-tuigreet \
    xdg-desktop-portal \
    xdg-desktop-portal-gtk

# --- Nix ---
if ! command -v nix &>/dev/null; then
    echo "==> Installing Nix..."
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    echo "Nix installed. Source the profile or restart shell, then re-run this script."
    echo "Run: . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    exit 0
else
    echo "==> Nix already installed"
fi

# --- Home Manager ---
if ! command -v home-manager &>/dev/null; then
    echo "==> Installing Home Manager..."
    nix run home-manager/master -- init --switch --flake "$DOTFILES_DIR/nix#$HOME_MANAGER_FLAKE"
else
    echo "==> Updating Home Manager..."
    home-manager switch --flake "$DOTFILES_DIR/nix#$HOME_MANAGER_FLAKE"
fi

# --- keyd ---
echo "==> Configuring keyd..."
sudo mkdir -p /etc/keyd
sudo ln -sf "$DOTFILES_DIR/config/keyd/default.conf" /etc/keyd/default.conf
sudo systemctl enable --now keyd
sudo keyd reload || true

# --- DankMaterialShell ---
echo "==> Configuring DankMaterialShell..."
systemctl --user enable dms
systemctl --user add-wants niri.service dms

# --- greetd (login greeter) ---
echo "==> Configuring greetd..."
sudo tee /etc/greetd/config.toml > /dev/null <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --cmd niri-session"
user = "greetd"
EOF
sudo systemctl enable greetd
sudo systemctl set-default graphical.target

# --- Flatpak ---
echo "==> Setting up Flatpak..."
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "==> Installing Flatpak apps..."
flatpak install --user -y flathub app.zen_browser.zen || true

# --- Claude CLI ---
if ! command -v claude &>/dev/null; then
    echo "==> Installing Claude CLI..."
    curl -fsSL https://claude.ai/install.sh | bash
else
    echo "==> Claude CLI already installed"
fi

# --- Shell ---
ZSH_PATH="$HOME/.nix-profile/bin/zsh"
if [[ -x "$ZSH_PATH" ]] && ! grep -q "$ZSH_PATH" /etc/shells; then
    echo "==> Adding zsh to /etc/shells..."
    echo "$ZSH_PATH" | sudo tee -a /etc/shells
fi

if [[ "$SHELL" != "$ZSH_PATH" ]] && [[ -x "$ZSH_PATH" ]]; then
    echo "==> Changing shell to zsh..."
    chsh -s "$ZSH_PATH"
fi

# --- Widevine (optional, for DRM in browsers) ---
echo ""
echo "==> Widevine for DRM (optional)"
echo "To enable DRM content in browsers, run:"
echo "  gh repo clone AsahiLinux/widevine-installer"
echo "  cd widevine-installer && sudo ./widevine-installer"

echo ""
echo "=== Bootstrap complete ==="
echo ""
echo "Next steps:"
echo "1. Reboot to start greetd (login greeter)"
echo "2. Log in via tuigreet → niri-session starts automatically"
echo "3. Configure Zen browser, etc."
