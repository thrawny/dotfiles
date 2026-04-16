{
  pkgs,
  lib,
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
        fig = "docker compose";
        vim = "nvim";
        svh = "sudo nvim /etc/hosts";
        k = "kubectl";
        kp = "kubectl get pod";
        ka = "kubectl apply -f";
        kn = "kubectl -n kube-system";
        ku = "kubectl config use-context";
        gsha = "git rev-parse HEAD | cut -c1-9";
        hb = "gh repo view --web";
        b = "bat -p --pager=never";
        gcam = "git add -A && git commit -m";
      }
      // lib.optionalAttrs pkgs.stdenv.isDarwin {
        bu = "brew upgrade";
      }
      // {
        c = "claude";
        cy = "claude --dangerously-skip-permissions";
        pr = "gh pr create --web";
        gp = "git push --force-with-lease --force-if-includes";
        gw = "git worktree";
        tp = "terraform plan";
        ta = "terraform apply";
        taf = "terraform apply -auto-approve";
        cx = "codex";
        cxy = "codex --dangerously-bypass-approvals-and-sandbox";
        scx = "sandbox codex --dangerously-bypass-approvals-and-sandbox";
        sc = "sandbox claude --dangerously-skip-permissions";
        spi = "sandbox pi";
      }
      // lib.optionalAttrs pkgs.stdenv.isLinux {
        pbcopy = "wl-copy";
        pbpaste = "wl-paste";
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
          # Replicate Oh My Zsh's WORDCHARS behavior
          export WORDCHARS='_-'

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
          # ===== macOS: Homebrew =====
          if [[ "$(uname)" == "Darwin" ]]; then
            [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
            alias cct='security find-generic-password -s "Claude Code-credentials" -w | jq -c "{claudeAiOauth}"'
          fi

          # Homebrew completions (macOS)
          if type brew &>/dev/null; then
            FPATH=$(brew --prefix)/share/zsh/site-functions:$FPATH
          fi

          # ===== Completion Configuration =====
          zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
          zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
          zstyle ':completion:*' menu select

          # zmx: Homebrew installs don't ship _zmx into site-functions
          if type brew &> /dev/null && command -v zmx &> /dev/null; then
            source <(zmx completions zsh)
          fi

          # ===== kubectl =====
          if command -v kubectl &> /dev/null; then
            source <(kubectl completion zsh)
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
            cd "$(git-worktree-go "$1")"
          }


          function zmx-clear-all() {
            if ! command -v zmx >/dev/null 2>&1; then
              echo "zmx is not installed"
              return 1
            fi

            local killed=0
            while IFS= read -r session; do
              [[ -z "$session" ]] && continue
              zmx kill "$session"
              ((killed++))
            done < <(zmx list --short)

            if [[ $killed -eq 0 ]]; then
              echo "No zmx sessions to clear"
            fi
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
          # HM loads fzf, but vi-mode overrides keybindings - re-source after vi-mode init
          if [ -z "$NVIM" ]; then
            zvm_after_init() {
              source ${pkgs.fzf}/share/fzf/key-bindings.zsh
              source ${pkgs.fzf}/share/fzf/completion.zsh
            }
          else
            # In Neovim terminal, no vi-mode - load fzf directly
            source ${pkgs.fzf}/share/fzf/key-bindings.zsh
            source ${pkgs.fzf}/share/fzf/completion.zsh
            bindkey ^e end-of-line
          fi

          # Bind Ctrl+F to forward-word for partial autosuggestion accept
          bindkey ^F forward-word
          bindkey ^f forward-word

          # ===== Zoxide =====
          # Only init for interactive shells (avoids broken Claude Code snapshot)
          [[ -o interactive ]] && eval "$(zoxide init --cmd cd zsh)"

          # ===== Secrets & Local Overrides =====
          if [[ -z "$SANDBOX" ]] && [ -f ~/.secrets ]; then
            set -a
            source ~/.secrets
            set +a
          fi
          [ -f ~/.zsh.local ] && source ~/.zsh.local

          if [[ -n "$SANDBOX" ]]; then
            SAVEHIST=0
            unsetopt APPEND_HISTORY
            unsetopt INC_APPEND_HISTORY
            unsetopt SHARE_HISTORY
          fi
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
