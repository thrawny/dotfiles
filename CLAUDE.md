# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal dotfiles repository that manages development environment configuration across macOS and Ubuntu systems using Ansible. The setup automates the installation and configuration of development tools, shell environments, and application settings.

## Key Commands

### Python Environment Setup
- `uv sync` - Install all Python dependencies (Ansible)
- `uv add <package>` - Add new Python dependency
- `uv remove <package>` - Remove Python dependency
- Environment automatically activated via direnv when entering the directory

### Setup and Deployment
- `ansible-playbook main.yml` - Deploy all configurations and software
- `ansible-playbook main.yml --tags "osx"` - Deploy only macOS-specific configurations
- `ansible-playbook main.yml --tags "ubuntu"` - Deploy only Ubuntu-specific configurations
- When running the ansible playbook, run it with 'ansible-playbook main.yml'

### macOS Specific
- `brew bundle --file=osx/Brewfile` - Install all Homebrew packages
- `./osx/setup.sh` - Configure macOS system defaults
- `brew bundle cleanup --file=osx/Brewfile` - Remove packages not in Brewfile

### Git Repository Management
- `git-cleanup-repo` - Clean up merged branches and prune obsolete tracking branches (custom script in bin/)

## Architecture

### Ansible Structure
- `main.yml` - Main playbook that orchestrates all tasks
- `all_config.yml` - Cross-platform configuration symlinks (vim, zsh, git, etc.)
- `all_software.yml` - Cross-platform software installation (oh-my-zsh, plugins)
- `osx_config.yml` & `osx_software.yml` - macOS-specific configurations
- `ubuntu_config.yml` & `ubuntu_software.yml` - Ubuntu-specific configurations

### Key Directories
- `bin/` - Custom shell scripts and utilities
- `git/` - Git configuration files (gitconfig, gitignoreglobal)
- `nvim/` - Neovim configuration with Lua setup
- `shell/` - Shell configuration (zshrc, tmux.conf)
- `osx/` - macOS-specific files including Brewfiles and system defaults
- `misc/` - Miscellaneous configs (ghostty, direnv, themes, etc.)

### Configuration Management
The repository uses symlinks to connect dotfiles to their target locations:
- Shell configs → `~/.zshrc`, `~/.tmux.conf`
- Editor configs → `~/.vim`, `~/.config/nvim`
- Git configs → `~/.gitconfig`, `~/.gitignoreglobal`
- App configs → `~/.config/ghostty/config`, `~/.config/direnv/direnvrc`

### Development Environment
- **Shell**: ZSH with oh-my-zsh and custom "thrawny" theme
- **Editor**: Neovim with Lua configuration, telescope, and various plugins
- **Terminal**: Support for both iTerm2 (macOS) and ghostty
- **Package Management**: Homebrew (macOS), APT (Ubuntu), asdf for runtime versions, uv for Python
- **Version Control**: Git with custom aliases and cleanup scripts
- **Python Environment**: Managed by uv with automatic activation via direnv

## Important Aliases and Functions

### Git Aliases
- `gcam` - git add -A && git commit -m
- `gcm` - git commit -m  
- `gp` - git push --force-with-lease --force-if-includes
- `gpo` - git push -u origin current_branch
- `gcr` - git-cleanup-repo (clean merged branches)

### Kubernetes/Docker
- `k` - kubectl
- `kt` - stern (log tailing)
- `fig` - docker-compose

### Development
- `vim` - aliased to nvim
- `cat` - aliased to bat with custom theme
- `gotest` - golangci-lint fmt && golangci-lint run --fix && go test

## Path Modifications
Custom binaries are added from:
- `$HOME/dotfiles/bin` - Custom scripts
- `$HOME/.local/bin` - User-installed binaries
- `$HOME/.claude/local` - Claude Code binaries