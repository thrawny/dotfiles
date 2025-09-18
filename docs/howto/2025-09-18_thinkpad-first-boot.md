# Quickstart: First Boot on the ThinkPad T14

Minimal checklist for the very first boot after installing stock NixOS (no desktop selected) and logging in on the ThinkPad.

1. **Get on Wi-Fi**
   ```bash
   sudo -i
   nmtui  # Activate a connection → pick your SSID → enter password
   ping nixos.org -c3  # optional connectivity sanity check
   ```

2. **Install git and grab the dotfiles repo**
   ```bash
   nix-shell -p git --run 'git clone https://github.com/jonas/dotfiles.git ~/dotfiles'
   cd ~/dotfiles
   ```

3. **Capture the laptop hardware profile**
   ```bash
   sudo nixos-generate-config --root /
   sudo cp /etc/nixos/hardware-configuration.nix \
     nix/hosts/thinkpad/hardware-configuration.nix
   ```

4. **Build the host configuration**
   ```bash
   nix build ./nix#nixosConfigurations.thinkpad.config.system.build.toplevel
   ```

5. **Activate it**
   ```bash
   sudo nixos-rebuild switch --flake ./nix#thinkpad
   ```

6. **(Optional) Commit & sync back**
   ```bash
   git add nix/hosts/thinkpad/hardware-configuration.nix
   git commit -m "Add ThinkPad hardware profile"
   git push
   ```

That’s it—future changes just repeat steps 4–5 after editing the repo.
