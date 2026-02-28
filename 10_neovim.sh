#!/bin/bash
# Phase 2 — Dev tools
# Installs the latest Neovim AppImage to ~/.local/bin/nvim.
set -euo pipefail

mkdir -p ~/.local/bin
NVIM_VER=$(curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest \
  | grep -oP '"tag_name": "\K[^"]+')
curl -fsSL "https://github.com/neovim/neovim/releases/download/${NVIM_VER}/nvim-linux-x86_64.appimage" \
  -o ~/.local/bin/nvim
chmod u+x ~/.local/bin/nvim

echo "Neovim installed at ~/.local/bin/nvim"
echo "Note: if AppImage fails with FUSE errors, install libfuse2:"
echo "  sudo apt install libfuse2  (already included in 01_basics_linux.sh)"
