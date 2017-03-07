#!/bin/bash

sudo apt install \
  build-essential \
  libssl-dev \
  libffi-dev \
  python-dev \
  python-apt \
  python-pip

pip2 install --user virtualenv
virtualenv -p python2 --system-site-packages ~/dotfiles_venv
~/dotfiles_venv/bin/pip install ansible
