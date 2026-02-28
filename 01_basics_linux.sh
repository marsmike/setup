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
  git-delta direnv hyperfine lnav \
  libfuse2

# Install nvm and latest Node LTS
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
\. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm alias default 'lts/*'

# yq (mikefarah — YAML processor; apt version is a different tool)
sudo curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" \
  -o /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq

# glow (Markdown renderer — Charm apt repo)
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.charm.sh/apt/gpg.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
  | sudo tee /etc/apt/sources.list.d/charm.list
sudo apt update && sudo apt install -y glow

# watchexec (trigger scripts on file changes — not in apt)
TMP=$(mktemp -d)
WATCHEXEC_VER=$(curl -fsSL https://api.github.com/repos/watchexec/watchexec/releases/latest \
  | grep -oP '"tag_name": "v\K[^"]+')
curl -fsSL "https://github.com/watchexec/watchexec/releases/latest/download/watchexec-${WATCHEXEC_VER}-x86_64-unknown-linux-musl.tar.xz" \
  | tar -xJf - -C "$TMP"
sudo install "$(find "$TMP" -name watchexec -type f)" /usr/local/bin/watchexec
rm -rf "$TMP"

# csvlens (CSV TUI viewer)
TMP=$(mktemp -d)
curl -fsSL "https://github.com/YS-L/csvlens/releases/latest/download/csvlens-x86_64-unknown-linux-musl.tar.xz" \
  | tar -xJf - -C "$TMP"
sudo install "$(find "$TMP" -name csvlens -type f)" /usr/local/bin/csvlens
rm -rf "$TMP"

# models (browse AI providers, pricing, benchmarks, agent changelogs)
TMP=$(mktemp -d)
curl -fsSL "https://github.com/arimxyer/models/releases/latest/download/models-x86_64-unknown-linux-gnu.tar.gz" \
  | tar -xzf - -C "$TMP"
sudo install "$(find "$TMP" -name models -type f)" /usr/local/bin/models
rm -rf "$TMP"

echo "Basics installed. Next: 02_dotfiles.sh then 03_shell.sh"
