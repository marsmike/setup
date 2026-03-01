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

# Register personal plugin marketplace (idempotent)
echo ""
echo "Registering personal Claude plugin marketplace..."
KNOWN_MARKETPLACES="${HOME}/.claude/plugins/known_marketplaces.json"
if [ -f "${KNOWN_MARKETPLACES}" ] && jq -e '."mike-plugins"' "${KNOWN_MARKETPLACES}" &>/dev/null; then
    echo "Marketplace 'mike-plugins' already registered, skipping."
else
    claude plugin marketplace add marsmike/claude-plugins --scope user
    echo "Marketplace registered. Install plugins with: claude plugin install <name>@mike-plugins"
fi
