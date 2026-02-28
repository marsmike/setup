#!/bin/bash
# Phase 3 — Optional
# Installs Nerd Fonts (JetBrainsMono + MesloLGS NF) for terminal use.
# Note: chezmoi dotfiles already manage MesloLGS fonts for dotfiles users.
set -euo pipefail

FONT_DIR="${HOME}/.local/share/fonts"
mkdir -p "${FONT_DIR}"

install_nerd_font() {
  local font="$1"
  local version
  version=$(curl -sL "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" \
    | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  echo "Installing ${font} Nerd Font ${version}..."
  curl -LO "https://github.com/ryanoasis/nerd-fonts/releases/download/${version}/${font}.tar.xz"
  tar -xf "${font}.tar.xz" -C "${FONT_DIR}"
  rm "${font}.tar.xz"
}

install_nerd_font "JetBrainsMono"
install_nerd_font "Meslo"

fc-cache -fv

echo ""
echo "Fonts installed to ${FONT_DIR}"
echo "Set your terminal font to 'JetBrainsMono Nerd Font' or 'MesloLGS NF'."
