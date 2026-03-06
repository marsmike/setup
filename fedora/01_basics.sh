#!/bin/bash
# Phase 1 — Packages (Fedora/RHEL/Rocky/Alma)
# Installs baseline packages and universal CLI tools.
# Run before any other phase scripts.
set -euo pipefail

if ! command -v dnf &>/dev/null; then
  echo "ERROR: dnf not found — this script requires Fedora/RHEL/Rocky/AlmaLinux." >&2
  exit 1
fi

sudo dnf install -y \
  git curl gcc gcc-c++ make \
  docker-compose btop htop gh vim wget \
  python3 python3-pip \
  zoxide ncdu tealdeer httpie powertop fzf bat ack bind-utils rsync jq tmux zsh \
  eza ripgrep fd-find ranger \
  git-delta direnv hyperfine lnav \
  fuse

# glow (Markdown renderer — Charm yum repo)
if ! command -v glow &>/dev/null; then
  cat <<EOF | sudo tee /etc/yum.repos.d/charm.repo
[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key
EOF
  sudo dnf install -y glow
fi

# ghostty (GPU terminal — only when a display is available)
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  sudo dnf install -y flatpak
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install -y flathub org.ghostty.ghostty || true
else
  echo "Skipping Ghostty (no display detected — headless server)"
fi

# ==============================================================================
# Cross-platform universal tools
# ==============================================================================

# Install nvm and latest Node LTS
if [ ! -d "$HOME/.nvm" ]; then
  NVM_VER=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep -oP '"tag_name": "\K[^"]+')
  curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VER}/install.sh" | bash
fi
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm alias default 'lts/*'

# yq (mikefarah — YAML processor)
if ! command -v yq &>/dev/null; then
  sudo curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" \
    -o /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq || echo "Failed to install yq"
fi

# watchexec (trigger scripts on file changes)
if ! command -v watchexec &>/dev/null; then
  TMP=$(mktemp -d)
  WATCHEXEC_VER=$(curl -fsSL https://api.github.com/repos/watchexec/watchexec/releases/latest | grep -oP '"tag_name": "v\K[^"]+')
  if curl -fsSL "https://github.com/watchexec/watchexec/releases/latest/download/watchexec-${WATCHEXEC_VER}-x86_64-unknown-linux-musl.tar.xz" \
    | tar -xJf - -C "$TMP"; then
    sudo install "$(find "$TMP" -name watchexec -type f)" /usr/local/bin/watchexec
  fi
  rm -rf "$TMP"
fi

# csvlens (CSV TUI viewer)
if ! command -v csvlens &>/dev/null; then
  TMP=$(mktemp -d)
  if curl -fsSL "https://github.com/YS-L/csvlens/releases/latest/download/csvlens-x86_64-unknown-linux-musl.tar.xz" \
    | tar -xJf - -C "$TMP"; then
    sudo install "$(find "$TMP" -name csvlens -type f)" /usr/local/bin/csvlens
  fi
  rm -rf "$TMP"
fi

# models (browse AI providers, pricing, benchmarks, agent changelogs)
if ! command -v models &>/dev/null; then
  TMP=$(mktemp -d)
  if curl -fsSL "https://github.com/arimxyer/models/releases/latest/download/models-x86_64-unknown-linux-gnu.tar.gz" \
    | tar -xzf - -C "$TMP"; then
    sudo install "$(find "$TMP" -name models -type f)" /usr/local/bin/models
  fi
  rm -rf "$TMP"
fi

# ==============================================================================
# bun (JavaScript runtime / bundler)
# ==============================================================================
if ! command -v bun &>/dev/null; then
  curl -fsSL https://bun.sh/install | bash || echo "Failed to install bun"
fi

# ==============================================================================
# yt-dlp (YouTube/media downloader)
# ==============================================================================
if ! command -v yt-dlp &>/dev/null; then
  mkdir -p ~/.local/bin
  curl -fsSL "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" \
    -o ~/.local/bin/yt-dlp && chmod +x ~/.local/bin/yt-dlp || echo "Failed to install yt-dlp"
fi

echo "Basics installed. Next: 02_shell.sh then 03_dotfiles.sh"
