#!/bin/bash
# Phase 3 — Optional
# Installs atuin — magical shell history with sync, search, and stats.
# Replaces mcfly.
set -euo pipefail

curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh

echo ""
echo "atuin installed."
echo ""
echo "Next steps:"
echo "  1. Migrate existing history:  atuin import auto"
echo "  2. Update ~/.zshrc — replace mcfly eval with:"
echo '     eval "$(atuin init zsh)"'
echo "  3. Optional sync:             atuin register / atuin login"
