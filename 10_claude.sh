#!/bin/bash
# Phase 2 — Claude Code
# Native installer + shell integration. Extend this script with
# MCP servers, project templates, keybindings, and other customisation.
set -euo pipefail

echo "Installing Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash
export PATH="$HOME/.local/bin:$PATH"

echo ""
echo "Claude Code $(claude --version) installed."
echo "Run 'claude' to get started."
