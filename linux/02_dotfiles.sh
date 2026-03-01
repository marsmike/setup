#!/bin/bash
# Phase 1 — Core (every machine)
# Installs chezmoi and applies dotfiles (repo set via DOTFILES_REPO, defaults to marsmike/dotfiles).
# Also bootstraps tmux plugin manager (tpm).
#
# GitHub auth: place a GH_TOKEN in .env next to this script or in the repo root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- load .env if present (tokens, secrets) ---
for ENV_FILE in "${SCRIPT_DIR}/.env" "${REPO_ROOT}/.env"; do
  if [ -f "$ENV_FILE" ]; then
    echo "Loading $ENV_FILE ..."
    set -o allexport
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +o allexport
  fi
done

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

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/marsmike/dotfiles.git}"
echo "Installing chezmoi and applying dotfiles from ${DOTFILES_REPO}..."
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply --force "${DOTFILES_REPO}"

# Ensure nvm init survives in .zshrc after chezmoi applies dotfiles
if [ -f "${HOME}/.zshrc" ] && ! grep -q 'NVM_DIR' "${HOME}/.zshrc"; then
  cat >> "${HOME}/.zshrc" << 'EOF'

# nvm (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF
fi

echo ""
echo "Loading Tmux Plugin Manager (tpm)..."
if [ ! -d ~/.tmux/plugins/tpm ]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
else
  echo "tpm already installed, skipping."
fi

echo ""
echo "Done! Start a new tmux session and press prefix+I to install plugins."
