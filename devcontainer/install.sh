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
}

main "$@"
