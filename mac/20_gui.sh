#!/bin/bash
# Phase 20 — GUI applications (macOS)
# Installs: Obsidian, Discord, WezTerm
# Note: ghostty is already installed in 01_basics.sh
set -euo pipefail

brew install --cask \
  obsidian \
  discord \
  wezterm

echo ""
echo "GUI apps installed: Obsidian, Discord, WezTerm"
