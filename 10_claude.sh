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
# Note: chezmoi deploys settings.json with extraKnownMarketplaces, which is the
# actual registration mechanism. This block covers machines where chezmoi hasn't run yet.
echo ""
echo "Registering personal Claude plugin marketplace..."
SETTINGS_FILE="${HOME}/.claude/settings.json"
if [ -f "${SETTINGS_FILE}" ] && jq -e '.extraKnownMarketplaces."mike-plugins"' "${SETTINGS_FILE}" &>/dev/null; then
    echo "Marketplace 'mike-plugins' already registered, skipping."
else
    claude plugin marketplace add marsmike/claude-plugins --scope user
    echo "Marketplace registered. Install plugins with: claude plugin install <name>@mike-plugins"
fi
