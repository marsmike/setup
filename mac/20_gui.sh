#!/bin/bash
# Phase 20 — GUI applications (macOS)
# Installs: Obsidian, Discord, WezTerm
# Note: ghostty is already installed in 01_basics.sh
#
# Soft-fail per cask so one broken app never aborts the rest.
set -euo pipefail

command -v brew &>/dev/null || { echo "ERROR: brew not found — run 01_basics.sh first"; exit 1; }

FAILED=()
cask_install() {
  if brew list --cask --versions "$1" &>/dev/null; then
    echo "  ✓ ${1} (already installed)"; return 0
  fi
  echo "  → installing cask $1 ..."
  brew install --cask "$1" || { echo "  ✗ FAILED: $1"; FAILED+=("$1"); }
}

for c in obsidian discord wezterm; do
  cask_install "$c"
done

echo ""
if [ ${#FAILED[@]} -eq 0 ]; then
  echo "✅ GUI apps installed: Obsidian, Discord, WezTerm"
else
  echo "⚠️  Completed with failure(s): ${FAILED[*]}"
fi
