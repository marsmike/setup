#!/bin/bash
# Phase 1 — Core (every Linux machine)
# Installs baseline packages. Run before any other phase scripts.
set -euo pipefail

sudo add-apt-repository universe
sudo apt update
sudo apt -y install \
  git apt-transport-https ca-certificates curl build-essential \
  docker-compose btop htop gh vim wget \
  python3 python3-pip python3-venv \
  zoxide ncdu tldr httpie powertop fzf bat ack dnsutils rsync jq tmux zsh \
  eza ripgrep fd-find \
  libfuse2

# Install nvm and latest Node LTS
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
\. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm alias default 'lts/*'

echo "Basics installed. Next: 02_dotfiles.sh then 03_shell.sh"
