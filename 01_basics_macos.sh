#!/bin/bash
# Phase 1 — Core (macOS)
# Installs Homebrew (if missing) and baseline packages.
set -euo pipefail

# Install Homebrew if not present
if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

brew install \
  git gh vim wget \
  zoxide fzf bat jq tmux zsh btop ncdu tldr httpie rsync \
  eza ripgrep fd \
  lazygit \
  nvm

# Install latest Node LTS via nvm
mkdir -p ~/.nvm
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
\. "$(brew --prefix nvm)/nvm.sh"
nvm install --lts
nvm use --lts
nvm alias default 'lts/*'

echo ""
echo "Note: Docker Desktop must be installed manually from https://www.docker.com/products/docker-desktop/"
echo "Next: 02_dotfiles.sh then 03_shell.sh"
