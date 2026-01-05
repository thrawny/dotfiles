# Asahi Linux Setup Guide

Configuring Fedora Asahi Linux on MacBook Air with Niri + DankMaterialShell.

## Prerequisites

- Fedora Asahi Linux installed
- Internet connection
- This dotfiles repo cloned to `~/dotfiles`

## Setup

Run the bootstrap script:

```bash
cd ~/dotfiles
./scripts/bootstrap-asahi-fedora.sh
```

The script handles:
- Disabling SELinux
- DNF updates and COPR repos
- Niri, Ghostty, keyd, DMS, greetd, and other packages
- Nix and Home Manager installation
- keyd configuration and service
- greetd login greeter (starts niri-session automatically)
- Flatpak apps (Zen browser)
- Claude CLI
- Shell change to zsh

After Nix installs, source the profile and re-run:
```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
./scripts/bootstrap-asahi-fedora.sh
```

Reboot when complete. Log in via tuigreet and niri-session starts automatically.

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

## Widevine (DRM for browsers)

For streaming services that require DRM:

```bash
gh repo clone AsahiLinux/widevine-installer
cd widevine-installer && sudo ./widevine-installer
```

## Troubleshooting

### Black screen on niri start
Check niri config in `nix/home/shared/niri.nix` - may need to set `render-drm-device`.

### Display scaling
Adjust scale in `nix/home/shared/niri.nix` under the output configuration.

### XWayland apps not working
Ensure xwayland-satellite service is running:
```bash
systemctl --user status xwayland-satellite
```

### keyd not working
Check service status and reload:
```bash
sudo systemctl status keyd
sudo keyd reload
```

### greetd not starting on boot
Ensure graphical target is set:
```bash
sudo systemctl set-default graphical.target
```
