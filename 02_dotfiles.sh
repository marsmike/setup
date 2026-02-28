#!/bin/bash
# Phase 1 — Core (every machine)
# Installs chezmoi and applies marsmike dotfiles.
# Also bootstraps tmux plugin manager (tpm).
set -e

echo "Installing chezmoi and applying dotfiles from marsmike/dotfiles..."
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply marsmike

echo ""
echo "Loading Tmux Plugin Manager (tpm)..."
if [ ! -d ~/.tmux/plugins/tpm ]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
else
  echo "tpm already installed, skipping."
fi

echo ""
echo "Done! Start a new tmux session and press prefix+I to install plugins."
