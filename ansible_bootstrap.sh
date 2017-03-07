#!/bin/bash

sudo apt install \
  build-essential \
  libssl-dev \
  libffi-dev \
  python-dev \
  python-apt \
  python-pip \
  curl

pip2 install --user virtualenv
virtualenv -p python2 --system-site-packages ~/dotfiles_venv
~/dotfiles_venv/bin/pip install ansible
~/dotfiles_venv/bin/ansible-playbook -K ~/dotfiles/main.yml
