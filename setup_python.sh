#!/bin/bash


answer_is_yes() {
  [[ "$REPLY" =~ ^[Yy]$ ]] \
    && return 0 \
    || return 1
}

ask() {
  print_question "$1"
  read
}

ask_for_confirmation() {
  print_question "$1 (y/n) "
  read -n 1
  printf "\n"
}

ask_for_sudo() {

  # Ask for the administrator password upfront
  sudo -v

  # Update existing `sudo` time stamp until this script has finished
  # https://gist.github.com/cowboy/3118588
  while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" || exit
  done &> /dev/null &

}

cmd_exists() {
  [ -x "$(command -v "$1")" ] \
    && printf 0 \
    || printf 1
}

execute() {
  $1 &> /dev/null
  print_result $? "${2:-$1}"
}

get_answer() {
  printf "$REPLY"
}

get_os() {

  declare -r OS_NAME="$(uname -s)"
  local os=""

  if [ "$OS_NAME" == "Darwin" ]; then
    os="osx"
  elif [ "$OS_NAME" == "Linux" ] && [ -e "/etc/lsb-release" ]; then
    os="ubuntu"
  fi

  printf "%s" "$os"

}

is_git_repository() {
  [ "$(git rev-parse &>/dev/null; printf $?)" -eq 0 ] \
    && return 0 \
    || return 1
}

mkd() {
  if [ -n "$1" ]; then
    if [ -e "$1" ]; then
      if [ ! -d "$1" ]; then
        print_error "$1 - a file with the same name already exists!"
      else
        print_success "$1"
      fi
    else
      execute "mkdir -p $1" "$1"
    fi
  fi
}

print_error() {
  # Print output in red
  printf "\e[0;31m  [✖] $1 $2\e[0m\n"
}

print_info() {
  # Print output in purple
  printf "\n\e[0;35m $1\e[0m\n\n"
}

print_question() {
  # Print output in yellow
  printf "\e[0;33m  [?] $1\e[0m"
}

print_result() {
  [ $1 -eq 0 ] \
    && print_success "$2" \
    || print_error "$2"

  [ "$3" == "true" ] && [ $1 -ne 0 ] \
    && exit
}

print_success() {
  # Print output in green
  printf "\e[0;32m  [✔] $1\e[0m\n"
}

install_pip() {
  local os=$(get_os)
  if [ "$os" = "ubuntu" ]; then
    if ! cmd_exists "pip2"; then
      ask_for_sudo
      sudo apt install python-pip
      pip2 install --upgrade pip
    else
      print_success "pip2 is already installed"
    fi

    if ! cmd_exists "pip3"; then
      ask_for_sudo
      sudo apt install python3-pip
      pip3 install --upgrade pip
    else
      print_success "pip3 is already installed"
    fi

  fi
}

install_virtualenvwrapper() {
  local os=$(get_os)
  if [ "$os" = "ubuntu" ]; then
    if ! cmd_exists "workon"; then
      pip3 install --user virtualenvwrapper
    else
      print_success "virtualenvwrapper is already installed"
    fi
    if [ ! -f ~/.zsh.local ]; then
      print_info "Writing virtualenvwrapper conf to ~/.zsh.local"
      echo "export VIRTUALENVWRAPPER_PYTHON=/usr/bin/python3" > ~/.zsh.local
      echo "source ~/.local/bin/virtualenvwrapper.sh" >> ~/.zsh.local
      print_success "Done"
    else
      print_info "~/.zsh.local already exists. Make sure it has virtualenvwrapper conf."
    fi

  fi
}


main() {
  install_pip
  install_virtualenvwrapper

}


main
