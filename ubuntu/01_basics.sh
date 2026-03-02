#!/bin/bash
# Phase 1 — Packages (Ubuntu/Debian/Mint)
# Installs baseline packages and universal CLI tools.
# Run before any other phase scripts.
set -euo pipefail

if ! command -v apt &>/dev/null; then
  echo "ERROR: apt not found — this script requires Ubuntu/Debian/Mint." >&2
  exit 1
fi

sudo add-apt-repository -y universe || true
sudo apt update

# Detect correct libfuse2 package name (Ubuntu 22.10+ renamed it)
LIBFUSE=$(apt-cache show libfuse2t64 &>/dev/null && echo libfuse2t64 || echo libfuse2)

sudo apt -y install \
  git apt-transport-https ca-certificates curl build-essential \
  btop htop gh vim wget \
  python3 python3-pip python3-venv \
  zoxide ncdu tldr httpie powertop fzf bat ack dnsutils rsync jq tmux zsh \
  eza ripgrep fd-find ranger \
  git-delta direnv hyperfine lnav \
  "$LIBFUSE"

# On Ubuntu, bat is installed as 'batcat' — create a user-level symlink
mkdir -p ~/.local/bin
[ -f /usr/bin/batcat ] && ln -sf /usr/bin/batcat ~/.local/bin/bat

# fd-find is installed as 'fdfind' — create a user-level symlink
[ -f /usr/bin/fdfind ] && ln -sf /usr/bin/fdfind ~/.local/bin/fd

# Docker Engine (official repo + compose plugin)
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
fi

# glow (Markdown renderer — Charm apt repo)
if ! command -v glow &>/dev/null; then
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/charm.gpg
  echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
  sudo apt update && sudo apt install -y glow
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

# just (command runner)
if ! command -v just &>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to ~/.local/bin
fi

# sops (secret encryption)
if ! command -v sops &>/dev/null; then
  SOPS_VER=$(curl -sL "https://api.github.com/repos/getsops/sops/releases/latest" \
    | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL "https://github.com/getsops/sops/releases/download/v${SOPS_VER}/sops-v${SOPS_VER}.linux.amd64" \
    -o "$TMP/sops"
  install "$TMP/sops" ~/.local/bin/sops
  trap - EXIT; rm -rf "$TMP"
fi

# ollama (local LLMs)
if ! command -v ollama &>/dev/null; then
  curl -fsSL https://ollama.com/install.sh | sh
fi

# ==============================================================================
# Neovim (AppImage → ~/.local/bin/nvim)
# ==============================================================================
NVIM_VER=$(curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest \
  | grep -oP '"tag_name": "\K[^"]+')
curl -fsSL "https://github.com/neovim/neovim/releases/download/${NVIM_VER}/nvim-linux-x86_64.appimage" \
  -o ~/.local/bin/nvim
chmod u+x ~/.local/bin/nvim
echo "Neovim ${NVIM_VER} installed at ~/.local/bin/nvim"

# ==============================================================================
# uv (Python package manager)
# ==============================================================================
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"

# ==============================================================================
# restic (backup tool)
# ==============================================================================
sudo apt install -y restic
sudo restic self-update

# ==============================================================================
# lazygit
# ==============================================================================
LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" \
  | grep -Po '"tag_name": "v\K[^"]*')
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -Lo "$TMP/lazygit.tar.gz" \
  "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
tar xf "$TMP/lazygit.tar.gz" -C "$TMP" lazygit
install "$TMP/lazygit" ~/.local/bin/lazygit
trap - EXIT
rm -rf "$TMP"

# ==============================================================================
# atuin (shell history — binary only; shell integration managed by dotfiles)
# ==============================================================================
curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh

# ==============================================================================
# Nerd Fonts (JetBrainsMono + Meslo)
# ==============================================================================
FONT_DIR="${HOME}/.local/share/fonts"
mkdir -p "${FONT_DIR}"
install_nerd_font() {
  local font="$1"
  local version
  version=$(curl -sL "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" \
    | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  echo "Installing ${font} Nerd Font ${version}..."
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' RETURN
  curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${version}/${font}.tar.xz" \
    -o "$TMP/${font}.tar.xz"
  tar -xf "$TMP/${font}.tar.xz" -C "${FONT_DIR}"
}
install_nerd_font "JetBrainsMono"
install_nerd_font "Meslo"
fc-cache -fv

# ==============================================================================
# Claude Code
# ==============================================================================
echo "Installing Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash
export PATH="$HOME/.local/bin:$PATH"
echo "Claude Code $(claude --version) installed."
# Register personal plugin marketplace (idempotent; chezmoi settings.json is authoritative)
SETTINGS_FILE="${HOME}/.claude/settings.json"
if [ -f "${SETTINGS_FILE}" ] && jq -e '.extraKnownMarketplaces."mike-plugins"' "${SETTINGS_FILE}" &>/dev/null; then
  echo "Marketplace 'mike-plugins' already registered, skipping."
else
  claude plugin marketplace add https://github.com/marsmike/claude-plugins --scope user
fi

# ==============================================================================
# Gemini CLI + GitHub Copilot extension
# (requires nvm/node already loaded above)
# ==============================================================================
echo "Installing Gemini CLI..."
npm install -g @google/gemini-cli
echo "Installing GitHub Copilot CLI..."
npm install -g @github/copilot
echo "Installing OpenAI Codex CLI..."
npm install -g @openai/codex

# ==============================================================================
# LLM CLI tools (Simon Willison stack + aider + pi)
# ==============================================================================
for tool in llm files-to-prompt ttok strip-tags aider-chat; do
  echo "Installing $tool..."
  uv tool install "$tool"
done

echo "Installing Pi coding agent..."
npm install -g @mariozechner/pi-coding-agent

echo "Basics installed. Next: 02_shell.sh then 03_dotfiles.sh"
