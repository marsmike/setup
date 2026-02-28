#!/bin/bash
# Phase 2 — Dev tools
# Installs the latest Neovim AppImage to ~/.local/bin/nvim.
set -euo pipefail

mkdir -p ~/.local/bin
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage
chmod u+x nvim.appimage
mv nvim.appimage ~/.local/bin/nvim

echo "Neovim installed at ~/.local/bin/nvim"
echo "Note: if AppImage fails with FUSE errors, install libfuse2:"
echo "  sudo apt install libfuse2  (already included in 01_basics_linux.sh)"
