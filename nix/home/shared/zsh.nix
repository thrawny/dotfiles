{
  config,
  pkgs,
  lib,
  dotfiles,
  ...
}:
{
  programs = {
    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      # Use nixpkgs zsh plugins
      plugins = [
        {
          name = "zsh-vi-mode";
          src = pkgs.zsh-vi-mode;
          file = "share/zsh-vi-mode/zsh-vi-mode.plugin.zsh";
        }
        {
          name = "zsh-history-substring-search";
          src = pkgs.zsh-history-substring-search;
          file = "share/zsh-history-substring-search/zsh-history-substring-search.zsh";
        }
        {
          name = "nix-shell";
          src = pkgs.zsh-nix-shell;
          file = "share/zsh-nix-shell/nix-shell.plugin.zsh";
        }
        {
          # OMZ git aliases only (gco, gst, gcan!, etc.)
          name = "omz-git";
          src = pkgs.oh-my-zsh;
          file = "share/oh-my-zsh/plugins/git/git.plugin.zsh";
        }
      ];

      history = {
        size = 50000;
        save = 50000;
        path = "$HOME/.zsh_history";
        extended = true;
        ignoreDups = true;
        ignoreSpace = true;
        share = true;
        append = true;
      };

      # Simple aliases (complex ones in initExtra)
      shellAliases = {
        h = "history";
        l = "ls -lh";
        fig = "docker-compose";
        vim = "nvim";
        svh = "sudo nvim /etc/hosts";
        k = "kubectl";
        kt = "stern";
        ka = "kubectl apply -f";
        kn = "kubectl -n kube-system";
        ki = "kubectl -n istio-system";
        kp = "kubectl get pods";
        gsha = "git rev-parse HEAD | cut -c1-9";
        ku = "kubectl config use-context";
        hb = "gh repo view --web";
        gotest = "golangci-lint fmt && golangci-lint run --fix && go test $(go list ./... | grep -v /lab/)";
        b = "bat -p --pager=never";
        gcam = "git add -A && git commit -m";
        tfa = "terraform apply";
        bu = "brew upgrade";
        c = "claude";
        cy = "claude --dangerously-skip-permissions";
        pr = "gh pr create --web";
        kd = "kubectl delete";
        gcm = "git commit -m";
        gp = "git push --force-with-lease --force-if-includes";
        gw = "git-gtr";
        tp = "terraform plan";
        ta = "terraform apply";
        taf = "terraform apply -auto-approve";
        ct = "cat ~/.codex/auth.json | jq -c";
      };

      # Set options
      setOptions = [
        "AUTO_CD"
        "AUTO_PUSHD"
        "PUSHD_IGNORE_DUPS"
        "PUSHDMINUS"
        "HIST_EXPIRE_DUPS_FIRST"
        "HIST_VERIFY"
        "INC_APPEND_HISTORY"
      ];

      initContent = lib.mkMerge [
        (lib.mkBefore ''
          # ===== Exports =====
          export PYTHONDONTWRITEBYTECODE=1
          export PYTHONUNBUFFERED=1
          export GOPATH=$HOME/go
          export EDITOR=nvim
          export AWS_PAGER=""
          export K9S_CONFIG_DIR=$HOME/.config/k9s
          export LANG=en_US.UTF-8
          export LC_ALL=en_US.UTF-8
          export LC_CTYPE=en_US.UTF-8

          # Replicate Oh My Zsh's WORDCHARS behavior
          export WORDCHARS='_-'

          # ===== PATH Configuration =====
          PATH=$PATH:$GOPATH/bin:$HOME/dotfiles/bin
          [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && PATH="$HOME/.local/bin:''${PATH}"
          [[ ":$PATH:" != *":$HOME/.claude/local:"* ]] && PATH="$HOME/.claude/local:''${PATH}"
          [[ ":$PATH:" != *":$HOME/.npm-global/bin:"* ]] && PATH="$HOME/.npm-global/bin:''${PATH}"
          export PATH

          # ===== zsh-vi-mode configuration (before plugin loads) =====
          # Disable vi mode when running inside Neovim terminal
          if [ -n "$NVIM" ]; then
            ZVM_INIT_MODE=sourcing  # Prevent zvm from initializing
          else
            ZVM_VI_INSERT_ESCAPE_BINDKEY=jk
            ZVM_LINE_INIT_MODE=$ZVM_MODE_INSERT
          fi

          # ===== Autosuggestion configuration (before plugin loads) =====
          ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS+=(
            forward-word
            emacs-forward-word
            vi-forward-word
          )
        '')
        ''
          # ===== OS-specific Configuration =====
          if [[ "$(uname)" == "Darwin" ]]; then
            [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
            alias cct='security find-generic-password -s "Claude Code-credentials" -w | jq -c "{claudeAiOauth}"'
          else
            alias pbcopy='wl-copy'
            alias pbpaste='wl-paste'
          fi

          # Homebrew completions (macOS)
          if type brew &>/dev/null; then
            FPATH=$(brew --prefix)/share/zsh/site-functions:$FPATH
          fi

          # ===== Completion Configuration =====
          zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
          zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
          zstyle ':completion:*' menu select

          # ===== kubectl =====
          if command -v kubectl &> /dev/null; then
            source <(kubectl completion zsh)
          fi

          if command -v dyff &> /dev/null; then
            export KUBECTL_EXTERNAL_DIFF="kubectl-dyff"
          fi

          # ===== Mise =====
          if command -v mise &>/dev/null && [[ -o interactive ]]; then
            eval "$(mise activate zsh)"
            source <(mise completion zsh)
          fi

          # ===== Conditional aliases =====
          if bat --version &>/dev/null && [[ -o interactive ]]; then
            alias cat='bat --style=grid,snip --theme "Monokai Extended Origin"'
          fi

          if command -v eza &>/dev/null && [[ -o interactive ]]; then
            alias ls='eza --icons --group-directories-first'
            # Monokai spectrum palette: purple dirs, orange exec, pink perms, cyan user
            export EZA_COLORS="di=38;5;141:ex=38;5;209:ln=38;5;141:ur=38;5;204:uw=38;5;204:ux=38;5;204:ue=38;5;204:gr=38;5;204:gw=38;5;204:gx=38;5;204:tr=38;5;204:tw=38;5;204:tx=38;5;204:uu=38;5;81:gu=38;5;81:da=38;5;243:sn=38;5;255:sb=38;5;243:ga=38;5;81:gm=38;5;227:gd=38;5;204:gv=38;5;141"
          fi

          # ===== Functions =====
          function gtrm() {
            git tag --delete $1 && git push --delete origin $1
          }

          function gpo() {
            git push -u origin $(git rev-parse --abbrev-ref HEAD)
          }

          function gwg() {
            cd "$(git gtr go "$1")"
          }

          function kcaev() {
            envsubst < $1 | kubectl apply -f -
          }

          function ktc() {
            stern $1 -c $1 -e "kube-probe|Checking status...|health check|Accepted connection from /100" ''${@:2}
          }

          function kcpf() {
            while true; do
              kubectl port-forward "$@"
            done
          }

          function dbp() {
            docker build -t $1 . && docker push $1
          }

          function ktjq() {
            stern $1 --output raw | jq -r -R 'fromjson? | "\(.["@timestamp"]) [\(.level)] - \(.message)"' ''${@:2}
          }

          function uuid() {
            python3 -c "import uuid;print(uuid.uuid4())"
          }

          function al() {
            profile=''${AWS_PROFILE:-default}
            aws sso login --profile $profile
          }

          function ecr_login() {
            ACCOUNT_ID=$(aws --profile $1 sts get-caller-identity --query Account --output text)
            REGION=$(aws --profile $1 configure get region)
            ECR_URL="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
            echo "Logging into ecr for profile $1 with ECR URL $ECR_URL"
            aws --profile $1 ecr get-login-password | docker login --username AWS --password-stdin $ECR_URL
          }

          # ===== vi-mode / fzf compatibility =====
          # fzf is initialized by HM, but vi-mode can override keybindings
          # Re-source fzf after vi-mode to restore keybindings
          if [ -z "$NVIM" ]; then
            zvm_after_init() {
              # Re-source fzf keybindings after vi-mode initialization
              [ -f "$HOME/.nix-profile/share/fzf/key-bindings.zsh" ] && source "$HOME/.nix-profile/share/fzf/key-bindings.zsh"
            }
          else
            # In Neovim terminal, no vi-mode, just set keybindings
            bindkey ^e end-of-line
          fi

          # Bind Ctrl+F to forward-word for partial autosuggestion accept
          bindkey ^F forward-word
          bindkey ^f forward-word

          # ===== Auto-start tmux in devpod =====
          if [[ -n "$DEVPOD" ]] && [[ -z "$TMUX" ]]; then
            tmux attach-session -t main 2>/dev/null || tmux new-session -s main
            exit
          fi

          if [[ -n "$DEVPOD" ]] && [[ -n "$TMUX" ]]; then
            alias exit='tmux detach'
          fi

          # ===== Zoxide =====
          # Only init for interactive shells (avoids broken Claude Code snapshot)
          [[ -o interactive ]] && eval "$(zoxide init --cmd cd zsh)"

          # ===== Local Overrides =====
          [ -f ~/.zsh.local ] && source ~/.zsh.local
        ''
      ];
      # Starship is configured separately in starship.nix
      # Direnv is configured separately in direnv.nix
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
      defaultOptions = [
        "--height 40%"
        "--layout=reverse"
        "--border"
        "--info=inline"
      ];
      fileWidgetOptions = [ "--preview 'bat --style=numbers --color=always --line-range :100 {}'" ];
      changeDirWidgetCommand = "fd --type d --hidden --follow --exclude .git --exclude .venv --exclude node_modules";
      defaultCommand = "fd --type f --hidden --follow --exclude .git --exclude .venv --exclude node_modules";
    };

    zoxide = {
      enable = true;
      # Manual integration below - conditional based on CLAUDE env var
      enableZshIntegration = false;
    };
  };
}
