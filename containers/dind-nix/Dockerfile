# =============================================================================
# Stage 1: Build Nix packages
# =============================================================================
FROM nixos/nix:latest AS builder

RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

WORKDIR /build
COPY nix/ ./nix/

# Build the devcontainer package
RUN nix build ./nix#devcontainer --out-link /tmp/env

# Extract the closure (all dependencies)
RUN mkdir -p /tmp/closure
RUN cp -R $(nix-store -qR /tmp/env/) /tmp/closure/

# =============================================================================
# Stage 2: Runtime image
# =============================================================================
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Minimal system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Copy Nix store and environment
COPY --from=builder /tmp/closure /nix/store
COPY --from=builder /tmp/env /nix/env

# Create dev user with docker group
RUN groupadd -f docker \
    && useradd -m -s /nix/env/bin/zsh -G sudo,docker dev \
    && echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/dev

# Environment
ENV PATH="/nix/env/bin:$PATH"
ENV SHELL="/nix/env/bin/zsh"
ENV DOCKER_HOST="unix:///var/run/docker.sock"
ENV HOME="/home/dev"
ENV USER="dev"

# Create required directories
RUN mkdir -p /var/run /var/log /workspace

# Set up PATH for login shells (bash) and zsh
RUN echo 'export PATH="/nix/env/bin:$PATH"' > /etc/profile.d/nix-path.sh \
    && echo 'export PATH="/nix/env/bin:$PATH"' > /home/dev/.zshenv \
    && chown dev:dev /home/dev/.zshenv

# =============================================================================
# Dotfiles
# =============================================================================
# Shell configs
COPY config/zsh/zshrc /home/dev/.zshrc
COPY config/tmux/tmux.conf /home/dev/.tmux.conf

# Git config
COPY config/git/gitconfig /home/dev/.gitconfig

# App configs in ~/.config/
COPY config/nvim /home/dev/.config/nvim
COPY config/lazygit /home/dev/.config/lazygit
COPY config/starship /home/dev/.config/starship
COPY config/k9s /home/dev/.config/k9s
COPY config/direnv /home/dev/.config/direnv

# Fix ownership (COPY creates files as root)
RUN chown -R dev:dev /home/dev

# Entrypoint script
COPY containers/dind-nix/docker-init.sh /usr/local/bin/docker-init
RUN chmod +x /usr/local/bin/docker-init

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/docker-init"]
CMD ["zsh"]
