.PHONY: switch fmt iso

# Rebuild and switch NixOS configuration (auto-detects hostname)
switch:
	sudo nixos-rebuild switch --flake ./nix#$$(hostname)

# Format all nix files
fmt:
	treefmt

# Build desktop installer ISO with network drivers
iso:
	nix build ./nix#packages.x86_64-linux.desktop-iso
	@echo "ISO created at: ./result/iso/"
	@echo "Write to USB with: sudo dd if=./result/iso/*.iso of=/dev/sdX bs=4M status=progress"
