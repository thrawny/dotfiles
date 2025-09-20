.PHONY: switch fmt

# Rebuild and switch NixOS configuration
switch:
	sudo nixos-rebuild switch --flake ./nix#thinkpad

# Format all nix files
fmt:
	treefmt