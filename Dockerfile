# syntax=docker/dockerfile:1.7
# Minimal image to test-build this dotfiles repo, run devcontainer/install.sh,
# and validate Ansible symlinks inside a disposable container.

ARG BASE_IMAGE=mcr.microsoft.com/devcontainers/base:ubuntu-24.04
FROM ${BASE_IMAGE} AS base

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    USER=vscode \
    HOME=/home/vscode \
    PATH=/home/vscode/.local/bin:/home/vscode/.cargo/bin:/home/vscode/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin

# System packages useful for the install script and common tooling.
# Keep this list lean; the script installs uv/mise/node as needed.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl git zsh sudo locales ripgrep tmux \
      openssh-client gnupg unzip xz-utils tar findutils less procps software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Configure UTF-8 locale
RUN echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen || true && (locale-gen || /usr/sbin/locale-gen || true)
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Create an unprivileged user with passwordless sudo (mirrors devcontainer defaults)
USER ${USER}
WORKDIR ${HOME}/dotfiles

# Install a recent Neovim on Ubuntu/Debian via PPA (works on ubuntu base)
RUN if grep -qi ubuntu /etc/os-release; then \
      sudo add-apt-repository -y ppa:neovim-ppa/unstable && \
      sudo apt-get update && \
      sudo apt-get install -y --no-install-recommends neovim; \
    else \
      echo "Non-Ubuntu base; using distro neovim if present"; \
      sudo apt-get update && sudo apt-get install -y --no-install-recommends neovim || true; \
    fi

# Copy repo contents
COPY --chown=${USER}:${USER} . ${HOME}/dotfiles

# Build args you may override to seed git config or tool creds (optional)
ARG GIT_USER
ARG GIT_EMAIL
ARG CLAUDE_CODE_CREDENTIALS
ARG CLAUDE_CODE_CONFIG
ARG CODEX_CREDENTIALS

# Run the devcontainer installer during build to catch failures early.
# This will:
# - install uv and mise
# - provision Python via uv if needed
# - uv sync + install project CLIs
# - run ansible to link dotfiles
# - optionally install Claude/Codex CLIs
RUN --mount=type=cache,target=${HOME}/.cache,uid=1000,gid=1000 \
    --mount=type=cache,target=/root/.cache \
    GIT_USER="${GIT_USER}" \
    GIT_EMAIL="${GIT_EMAIL}" \
    CLAUDE_CODE_CREDENTIALS="${CLAUDE_CODE_CREDENTIALS}" \
    CLAUDE_CODE_CONFIG="${CLAUDE_CODE_CONFIG}" \
    CODEX_CREDENTIALS="${CODEX_CREDENTIALS}" \
    bash -lc 'mise --version || true; echo PATH=$PATH; mise trust || true; bash devcontainer/install.sh'

# Default to zsh if available; override with `docker run ... bash` if desired.
SHELL ["/bin/bash", "-lc"]
CMD ["zsh", "-l"]
