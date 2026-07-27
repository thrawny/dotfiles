{ lib, pkgs, ... }:
{
  programs = {
    bash = {
      enable = true;
      enableCompletion = false;
      historyControl = [
        "ignoredups"
        "ignorespace"
      ];
      initExtra = lib.mkOrder 2000 ''
        # ZMX_TASK marks a `zmx run` session, which nobody is watching: render
        # no prompt so PS1/PS2 stay out of the scrollback `zmx history` returns.
        if [[ -n "$QUIET_PROMPT" || -n "$ZMX_TASK" ]]; then
          quiet_prompt=1
          # direnv otherwise writes its whole export list into the scrollback of
          # every task, which is more noise than the prompt ever was. Exported
          # because direnv reads it as a separate process.
          export DIRENV_LOG_FORMAT=
        fi

        if type bind >/dev/null 2>&1; then
          if shopt -q progcomp 2>/dev/null && [[ ! -v BASH_COMPLETION_VERSINFO ]]; then
            . "${pkgs.bash-completion}/etc/profile.d/bash_completion.sh"
          fi

          eval "$(${pkgs.direnv}/bin/direnv hook bash)"

          if [[ -n "$quiet_prompt" ]]; then
            PS1=
            PS2=
          elif [[ $TERM != "dumb" ]]; then
            eval "$(${pkgs.starship}/bin/starship init bash --print-full-init)"
          fi
        elif [[ -n "$quiet_prompt" ]]; then
          PS1=
          PS2=
        else
          PS1='bash:\W \$ '
        fi

        unset quiet_prompt
      '';
    };

    direnv.enableBashIntegration = false;
    fzf.enableBashIntegration = false;
    ghostty.enableBashIntegration = false;
    lazygit.enableBashIntegration = false;
    starship.enableBashIntegration = false;
    zoxide.enableBashIntegration = false;
  };
}
