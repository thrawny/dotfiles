FROM debian:trixie-slim AS linuxbrew

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      file \
      git \
      locales \
      perl \
      procps \
      unzip \
      xz-utils \
      zsh \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash linuxbrew \
    && mkdir -p /home/linuxbrew/.linuxbrew /opt \
    && chown -R linuxbrew:linuxbrew /home/linuxbrew/.linuxbrew

USER linuxbrew
RUN git clone --depth 1 https://github.com/Homebrew/brew /home/linuxbrew/.linuxbrew/Homebrew \
    && mkdir -p /home/linuxbrew/.linuxbrew/bin \
    && ln -s ../Homebrew/bin/brew /home/linuxbrew/.linuxbrew/bin/brew

USER root
RUN ln -s /home/linuxbrew/.linuxbrew /opt/homebrew

USER linuxbrew
ENV HOME=/home/linuxbrew \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PATH=/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/home/linuxbrew/.npm-global/bin:/usr/local/bin:/usr/bin:/bin

COPY --chown=linuxbrew:linuxbrew Brewfile /tmp/Brewfile
RUN brew update --quiet \
    && brew tap neurosnap/tap \
    && brew trust neurosnap/tap \
    && brew bundle --file /tmp/Brewfile \
    && brew cleanup --prune=all \
    && rm -rf /home/linuxbrew/.cache/Homebrew

FROM linuxbrew AS test
WORKDIR /home/linuxbrew/dotfiles
COPY --chown=linuxbrew:linuxbrew . .
ENV DOTFILES_SETUP_TESTING=1
RUN tests/macos-container-e2e.sh
CMD ["bin/check-macos"]
