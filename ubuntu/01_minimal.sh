#!/bin/bash
# Minimal alternative to 01_basics.sh (Ubuntu/Debian)
# Installs Claude Code, herdr and tmux, plus only what they and the dotfiles
# need. Follow with 02_shell.sh and 03_dotfiles.sh, as in the full pipeline.
#
# Dotfile requirements covered here:
#   jq             ~/.claude/settings.json modify script
#   zsh, zoxide    ~/.zshrc (oh-my-zsh itself comes from 02_shell.sh)
#   python3, git   Claude Code hooks and the repos chezmoi clones
#
# Not installed: Docker, Node, bun (so the Claude status line stays empty), and
# the other 01_basics.sh tools. Run 01_basics.sh later to add them. Safe to re-run.
#
# Claude's permission mode is set to auto through ~/.config/claude-permission-mode,
# which the dotfiles read. An existing file is left alone.
#
# Usage:
#   bash ubuntu/01_minimal.sh
#   bash ubuntu/02_shell.sh
#   bash ubuntu/03_dotfiles.sh
set -euo pipefail

sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o DPkg::Lock::Timeout=300 update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o DPkg::Lock::Timeout=300 install \
  ca-certificates curl git jq python3 tmux zoxide zsh

mkdir -p "${HOME}/.local/bin"
export PATH="${HOME}/.local/bin:${PATH}"

if command -v claude &>/dev/null; then
  echo "Claude Code already installed, skipping."
else
  echo "Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
fi

if command -v herdr &>/dev/null; then
  echo "herdr already installed, skipping."
else
  echo "Installing herdr..."
  curl -fsSL https://herdr.dev/install.sh | sh
fi

PERMISSION_MODE_FILE="${HOME}/.config/claude-permission-mode"
if [ ! -e "${PERMISSION_MODE_FILE}" ]; then
  mkdir -p "${HOME}/.config"
  echo auto > "${PERMISSION_MODE_FILE}"
fi

echo ""
echo "Installed: Claude Code $(claude --version), $(herdr --version), $(tmux -V)"
echo "Next: bash ubuntu/02_shell.sh, then bash ubuntu/03_dotfiles.sh"
