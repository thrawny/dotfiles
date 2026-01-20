FROM nixos/nix:latest

# Enable flakes
RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

# Set up as root with HOME=/root for simplicity
ENV HOME=/root
ENV USER=root

# Create profile directories
RUN mkdir -p /root/.local/state/nix/profiles \
    && mkdir -p /nix/var/nix/profiles/per-user/root

# Copy dotfiles repo
COPY . /root/dotfiles

WORKDIR /root/dotfiles

# Store paths from the store before wiping the profile
# Then clear all nix-env packages to avoid conflicts with home-manager
# Add nix to PATH so home-manager can find it, then run switch
# Also save the SSL cert path for runtime use
RUN NIX_BIN=$(readlink -f $(which nix)) \
    && NIX_DIR=$(dirname $NIX_BIN) \
    && SSL_CERT_FILE=$(find /nix/store -name "ca-bundle.crt" -path "*nss-cacert*" | head -1) \
    && echo "$SSL_CERT_FILE" > /tmp/ssl_cert_path \
    && nix-env -e '.*' \
    && export PATH=$NIX_DIR:$PATH \
    && export NIX_SSL_CERT_FILE=$SSL_CERT_FILE \
    && $NIX_BIN run nixpkgs#home-manager -- switch --flake ./nix#container -b backup

# Set SSL cert environment for runtime (git, curl, etc.)
RUN SSL_CERT=$(cat /tmp/ssl_cert_path) \
    && echo "export NIX_SSL_CERT_FILE=$SSL_CERT" >> /root/.zshenv \
    && echo "export SSL_CERT_FILE=$SSL_CERT" >> /root/.zshenv \
    && echo "export GIT_SSL_CAINFO=$SSL_CERT" >> /root/.zshenv

# Build nvim plugins (lazy.nvim)
RUN SSL_CERT=$(cat /tmp/ssl_cert_path) \
    && export NIX_SSL_CERT_FILE=$SSL_CERT \
    && export SSL_CERT_FILE=$SSL_CERT \
    && export GIT_SSL_CAINFO=$SSL_CERT \
    && /root/.nix-profile/bin/nvim --headless "+Lazy! sync" +qa

# Test that zsh works
RUN /root/.nix-profile/bin/zsh -c 'echo "zsh works!"'

WORKDIR /root/dotfiles
CMD ["/root/.nix-profile/bin/zsh"]
