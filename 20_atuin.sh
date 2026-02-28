#!/bin/bash
# Phase 3 — Optional
# Installs atuin — magical shell history with sync, search, and stats.
# Replaces mcfly.
set -euo pipefail

curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh

# --- patch .zshrc ---
ZSHRC="${HOME}/.zshrc"
if [ -f "${ZSHRC}" ]; then
  # Replace commented-out mcfly line (left by 03_shell.sh) with atuin
  if grep -q 'mcfly init' "${ZSHRC}"; then
    sed -i.bak 's|.*mcfly init.*|eval "$(atuin init zsh)"|' "${ZSHRC}" && rm -f "${ZSHRC}.bak"
    echo "Replaced mcfly line in .zshrc with atuin."
  # Or add atuin if neither is present
  elif ! grep -q 'atuin init' "${ZSHRC}"; then
    echo '' >> "${ZSHRC}"
    echo 'eval "$(atuin init zsh)"' >> "${ZSHRC}"
    echo "Added atuin init to .zshrc."
  else
    echo "atuin already in .zshrc, skipping."
  fi
fi

echo ""
echo "atuin installed."
echo "  Migrate history: atuin import auto"
echo "  Optional sync:   atuin register / atuin login"
