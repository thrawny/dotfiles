# NixOS and Home Manager commands

.PHONY: switch boot test build clean update

# Default target - rebuild and switch
switch:
	sudo nixos-rebuild switch --flake ./nix#thinkpad

# Build and switch on next boot
boot:
	sudo nixos-rebuild boot --flake ./nix#thinkpad

# Test build without switching
test:
	sudo nixos-rebuild test --flake ./nix#thinkpad

# Just build without activating
build:
	nixos-rebuild build --flake ./nix#thinkpad

# Update flake inputs
update:
	cd nix && nix flake update

# Garbage collection
clean:
	sudo nix-collect-garbage -d
	nix-collect-garbage -d

# Show current generation
info:
	nixos-rebuild list-generations

# Rollback to previous generation
rollback:
	sudo nixos-rebuild switch --rollback

# Format all nix files (using treefmt from nixfmt-tree)
fmt:
	treefmt

# Home manager only
home:
	home-manager switch --flake ./nix#thrawny