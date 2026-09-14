# Shared Bash/Zsh wrapper, matching Home Manager's `y` integration.
y() {
  local cwd_file cwd exit_code
  cwd_file=$(mktemp "${TMPDIR:-/tmp}/yazi-cwd.XXXXXX") || return
  yazi "$@" --cwd-file="$cwd_file"
  exit_code=$?
  if [[ -s "$cwd_file" ]]; then
    IFS= read -r cwd < "$cwd_file" || true
    if [[ -n "$cwd" && "$cwd" != "$PWD" ]]; then
      builtin cd -- "$cwd" || exit_code=$?
    fi
  fi
  rm -f -- "$cwd_file"
  return "$exit_code"
}
