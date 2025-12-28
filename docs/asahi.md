# Asahi Linux Setup Guide

Step-by-step guide for configuring Fedora Asahi Linux on MacBook Air with Niri + DankMaterialShell.

## Prerequisites

- Fedora Asahi Linux installed
- Internet connection
- This dotfiles repo cloned to `~/dotfiles`

## 1. Install Nix

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Restart your shell or run:
```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

## 2. Install DankMaterialShell

DMS provides the desktop shell (panel, launcher, lock screen, notifications, wallpaper).

```bash
# Enable COPR repo and install
sudo dnf copr enable avenge/dms
sudo dnf install dms

# Enable systemd service and bind to niri
systemctl --user enable dms
systemctl --user add-wants niri.service dms
```

## 3. Install Fedora Packages

Niri and other GUI components are installed via DNF (not Nix) for better hardware compatibility:

```bash
sudo dnf install niri ghostty playerctl wireplumber xwayland-satellite keyd
```

Optional for gaming:
```bash
sudo dnf install steam
```

## 4. Configure keyd (keyboard remapping)

keyd provides system-wide key remapping (Caps Lock → Escape, Alt ↔ Meta swap for Mac-like shortcuts):

```bash
sudo ln -sf ~/dotfiles/config/keyd/default.conf /etc/keyd/default.conf
sudo systemctl enable --now keyd
```

To reload after editing the config: `sudo keyd reload`

## 5. Install Home Manager

```bash
nix run home-manager/master -- init --switch --flake ~/dotfiles/nix#asahi-air
```

For subsequent updates:
```bash
home-manager switch --flake ~/dotfiles/nix#asahi-air
```

## 6. Configure Display Manager (Optional)

If you want to use a display manager instead of starting niri from TTY:

```bash
sudo dnf install greetd greetd-tuigreet
sudo systemctl enable greetd
```

Edit `/etc/greetd/config.toml`:
```toml
[default_session]
command = "tuigreet --cmd niri-session"
```

## 7. Start Niri

From TTY (if not using display manager):
```bash
niri-session
```

## Keybindings

| Key | Action |
|-----|--------|
| `Super+Space` | DMS Spotlight (app launcher) |
| `Alt+Return` | Ghostty terminal |
| `Alt+Escape` | DMS Lock screen |
| `Alt+W` | Close window |
| `Alt+H/J/K/L` | Focus left/down/up/right |
| `Alt+Shift+H/J/K/L` | Move window |
| `Alt+1-9` | Switch workspace |
| `Alt+Shift+Escape` | Quit niri |

## Flatpak Apps

Install Flathub and apps manually (flatpak handles updates automatically):

```bash
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub app.zen_browser.zen com.1password.1Password
```

## Troubleshooting

### Black screen on niri start
Uncomment the debug section in `config/niri/config.kdl`:
```kdl
debug {
    render-drm-device "/dev/dri/renderD128"
}
```

### Display scaling
Adjust scale in `config/niri/config.kdl`:
```kdl
output "eDP-1" {
    scale 2.0
}
```

### XWayland apps not working
Ensure xwayland-satellite service is running:
```bash
systemctl --user status xwayland-satellite
```
