# af-magic.zsh-theme
# Repo: https://github.com/andyfleming/oh-my-zsh
# Direct Link: https://github.com/andyfleming/oh-my-zsh/blob/master/themes/af-magic.zsh-theme
autoload -U colors; colors

if [ $UID -eq 0 ]; then NCOLOR="red"; else NCOLOR="green"; fi
local return_code="%(?..%{$fg[red]%}%? ↵%{$reset_color%})"

if [ -s "/opt/homebrew/etc/zsh-kubectl-prompt/kubectl.zsh" ]; then
  source /opt/homebrew/etc/zsh-kubectl-prompt/kubectl.zsh
  zstyle ':zsh-kubectl-prompt:' namespace false

  if [ "$TERM_PROGRAM" = "WarpTerminal" ]; then
    git rev-parse --is-inside-work-tree &>/dev/null && temp_git_prompt=" $(git_prompt_info) " || temp_git_prompt=""
    PROMPT='$FG[032]%~ $FG[237]$FG[032](${ZSH_KUBECTL_PROMPT}) $(git_prompt_info) $FG[105]%(!.#.»)%{$reset_color%} '
  else
    PROMPT='$FG[237]$FG[032](${ZSH_KUBECTL_PROMPT}) $FG[237]------------------------------------------------------------%{$reset_color%}
$FG[032]%~\
$(git_prompt_info) \
$FG[105]%(!.#.»)%{$reset_color%} '
  fi

else

  PROMPT='$FG[237]$FG[237]------------------------------------------------------------%{$reset_color%}
$FG[032]%~\
$(git_prompt_info) \
$FG[105]%(!.#.»)%{$reset_color%} '

fi

PROMPT2='%{$fg[red]%}\ %{$reset_color%}'
RPS1='${return_code}'

# color vars
eval my_gray='$FG[237]'
eval my_orange='$FG[214]'

# right prompt
# if type "virtualenv_prompt_info" > /dev/null
# then
# 	RPROMPT='$(virtualenv_prompt_info)' # $my_gray%n@%m%{$reset_color%}%'
# fi
# else
# 	RPROMPT='$my_gray%n@%m%{$reset_color%}%'
# fi
# RPROMPT='%{$fg[blue]%}($ZSH_KUBECTL_PROMPT)%{$reset_color%}'

# git settings
ZSH_THEME_GIT_PROMPT_PREFIX="$FG[075]($FG[078]"
ZSH_THEME_GIT_PROMPT_CLEAN=""
ZSH_THEME_GIT_PROMPT_DIRTY="$my_orange*%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="$FG[075])%{$reset_color%}"
