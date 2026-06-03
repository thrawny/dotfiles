{ lib, pkgs, ... }:
{
  programs.bash = {
    enable = true;
    enableCompletion = false;
    historyControl = [
      "ignoredups"
      "ignorespace"
    ];
    initExtra = lib.mkOrder 2000 ''
      if type bind >/dev/null 2>&1; then
        if shopt -q progcomp 2>/dev/null && [[ ! -v BASH_COMPLETION_VERSINFO ]]; then
          . "${pkgs.bash-completion}/etc/profile.d/bash_completion.sh"
        fi

        eval "$(${pkgs.direnv}/bin/direnv hook bash)"

        if [[ $TERM != "dumb" ]]; then
          eval "$(${pkgs.starship}/bin/starship init bash --print-full-init)"
        fi
      else
        PS1='bash:\W \$ '
      fi
    '';
  };
}
