#!/bin/bash
# Phase 1 — Core (every Linux machine)
# Installs baseline packages across multiple Linux distributions.
# Run before any other phase scripts.
set -euo pipefail

# Detect OS
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS=$ID
else
  echo "Unsupported OS (no /etc/os-release found)."
  exit 1
fi

echo "Detected OS: $OS"

if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
  sudo add-apt-repository -y universe || true
  sudo apt update
  sudo apt -y install \
    git apt-transport-https ca-certificates curl build-essential \
    docker-compose btop htop gh vim wget \
    python3 python3-pip python3-venv \
    zoxide ncdu tldr httpie powertop fzf bat ack dnsutils rsync jq tmux zsh \
    eza ripgrep fd-find ranger \
    git-delta direnv hyperfine lnav \
    libfuse2

  # On Ubuntu, bat is installed as 'batcat' — create a user-level symlink
  mkdir -p ~/.local/bin
  [ -f /usr/bin/batcat ] && ln -sf /usr/bin/batcat ~/.local/bin/bat

  # glow (Markdown renderer — Charm apt repo)
  if ! command -v glow &>/dev/null; then
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
    sudo apt update && sudo apt install -y glow
  fi

  # ghostty (GPU terminal)
  if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    sudo apt install -y flatpak
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak install -y flathub org.ghostty.ghostty || true
  else
    echo "Skipping Ghostty (no display detected — headless server)"
  fi

elif [[ "$OS" == "fedora" || "$OS" == "rhel" || "$OS" == "centos" || "$OS" == "rocky" || "$OS" == "almalinux" ]]; then
  
  # For Fedora Atomic variants (rpm-ostree), we typically avoid raw package installations here,
  # relying on Distrobox instead. We check if rpm-ostree is the primary manager.
  if command -v rpm-ostree &>/dev/null && [ -d /run/ostree-booted ]; then
    echo "Detected rpm-ostree (Fedora Atomic). Only installing essentials. Use Distrobox for the rest."
    # Can install layered packages if really needed, but generally discouraged.
    # We will just ensure curl and git exist.
  else
    sudo dnf install -y \
      git curl gcc gcc-c++ make \
      docker-compose btop htop gh vim wget \
      python3 python3-pip \
      zoxide ncdu tealdeer httpie powertop fzf bat ack bind-utils rsync jq tmux zsh \
      eza ripgrep fd-find ranger \
      git-delta direnv hyperfine lnav \
      fuse

    # glow (Markdown renderer)
    if ! command -v glow &>/dev/null; then
      sudo cat <<EOF | sudo tee /etc/yum.repos.d/charm.repo
[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key
EOF
      sudo dnf install -y glow
    fi

    if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
      sudo dnf install -y flatpak
      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
      flatpak install -y flathub org.ghostty.ghostty || true
    fi
  fi

elif [[ "$OS" == "arch" || "$OS" == "manjaro" || "$OS" == "endeavouros" ]]; then
  sudo pacman -Sy --noconfirm --needed \
    git curl base-devel \
    docker-compose btop htop github-cli vim wget \
    python python-pip \
    zoxide ncdu tealdeer httpie powertop fzf bat ack bind rsync jq tmux zsh \
    eza ripgrep fd ranger \
    git-delta direnv hyperfine lnav \
    fuse2 glow flatpak

  if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak install -y flathub org.ghostty.ghostty || true
  fi

else
  echo "WARNING: Unknown or unsupported OS ($OS). Skipping system package installations."
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

echo "Basics installed. Next: 02_dotfiles.sh then 03_shell.sh"