#!/usr/bin/env bash

[[ "${TRACE}" ]] && set -x
set -eou pipefail
shopt -s nullglob

main() {
    if ! uv --version &>/dev/null; then
        echo "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        PATH="$HOME/.local/bin:$PATH"
    fi

    if [ -f "$HOME/.zshrc" ]; then
        mv "$HOME/.zshrc" "$HOME/.zshrc.bak"
    fi
    if [ -f "$HOME/.gitconfig" ]; then
        mv "$HOME/.gitconfig" "$HOME/.gitconfig.bak"
    fi

    uv run ansible-playbook main.yml

    echo "Configuring git..."
    if [ -n "${GIT_USER:-}" ]; then
        git config --global user.name "$GIT_USER"
        echo "Set git user.name to $GIT_USER"
    fi
    if [ -n "${GIT_EMAIL:-}" ]; then
        git config --global user.email "$GIT_EMAIL"
        echo "Set git user.email to $GIT_EMAIL"
    fi

    echo "Attempting to change default shell to zsh..."
    if sudo chsh -s "$(which zsh)" "$USER" 2>/dev/null; then
        echo "Successfully changed default shell to zsh"
    else
        echo "Info: Could not change default shell to zsh (sudo access may not be available)"
    fi
}

main "$@"
