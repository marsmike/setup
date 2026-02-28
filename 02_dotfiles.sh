#!/bin/bash
# Phase 1 — Core (every machine)
# Installs chezmoi and applies marsmike dotfiles.
# Also bootstraps tmux plugin manager (tpm).
#
# GitHub auth: place a GH_TOKEN in .env next to this script (see .env.example).
set -euo pipefail

# --- load .env if present (tokens, secrets) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/.env" ]; then
  echo "Loading ${SCRIPT_DIR}/.env ..."
  set -o allexport
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/.env"
  set +o allexport
fi

# --- GitHub CLI auth ---
# gh is installed by 01_basics_*.sh; find it wherever it landed.
GH_BIN="$(command -v gh 2>/dev/null || echo "${HOME}/.local/bin/gh")"
if "$GH_BIN" auth status &>/dev/null; then
  echo "gh already authenticated, skipping."
elif [ -n "${GH_TOKEN:-}" ]; then
  echo "Authenticating gh via GH_TOKEN..."
  echo "$GH_TOKEN" | "$GH_BIN" auth login --with-token
else
  echo "Logging into GitHub (interactive)..."
  "$GH_BIN" auth login --hostname github.com --git-protocol https
fi

DOTFILES_REPO="${DOTFILES_REPO:-marsmike}"
echo "Installing chezmoi and applying dotfiles from ${DOTFILES_REPO}/dotfiles..."
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply --force "${DOTFILES_REPO}"

echo ""
echo "Loading Tmux Plugin Manager (tpm)..."
if [ ! -d ~/.tmux/plugins/tpm ]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
else
  echo "tpm already installed, skipping."
fi

echo ""
echo "Done! Start a new tmux session and press prefix+I to install plugins."
