# Unreal Tournament 2004 on NixOS

## Dependencies

The installer requires `7zip` and `unshield`, which aren't in the default NixOS environment. Provide them inline with `nix shell`.

## Installation

Run the OldUnreal installer from the [FullGameInstallers](https://github.com/OldUnreal/FullGameInstallers) repo:

```bash
nix shell nixpkgs#p7zip nixpkgs#unshield --command bash /path/to/FullGameInstallers/Linux/install-ut2004.sh -d ~/Games/UT2004
```

The installer will prompt you to accept the Epic Games Terms of Service and ask about desktop shortcuts.

The `ldconfig` warnings during "Apply UT2004 Specific Fixes" are harmless on NixOS and can be ignored.

## Running

The game requires `steam-run` for an FHS-compatible environment, and `SDL_VIDEODRIVER=x11` to fix mouse input on Wayland:

```bash
SDL_VIDEODRIVER=x11 steam-run ~/Games/UT2004/System/UT2004
```

The desktop entry at `~/.local/share/applications/OldUnreal-UT2004.desktop` is patched to include both of these.
