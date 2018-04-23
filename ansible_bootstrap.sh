#!/bin/bash

set -e

sudo apt install -y \
  build-essential \
  libssl-dev \
  libffi-dev \
  python3-dev \
  python3-apt \
  python3-setuptools \
  python3-venv \
  curl

curl https://bootstrap.pypa.io/get-pip.py | sudo python3

pip install --user virtualenv
python3 -m venv --system-site-packages ~/dotfiles_venv
~/dotfiles_venv/bin/pip install ansible

~/dotfiles_venv/bin/ansible-playbook -K ~/dotfiles/main.yml

chsh -s /usr/bin/zsh
env zsh
