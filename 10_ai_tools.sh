#!/bin/bash
# Phase 2 — Dev tools
# Installs AI coding assistants and LLM CLI utilities.
# Prerequisite: nvm + node LTS (included in 01_basics_linux.sh / 01_basics_macos.sh)
set -euo pipefail

# Load nvm so npm is available for npm-based tools
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck source=/dev/null
  \. "$NVM_DIR/nvm.sh"
elif command -v brew &>/dev/null && [ -s "$(brew --prefix nvm)/nvm.sh" ]; then
  # shellcheck source=/dev/null
  \. "$(brew --prefix nvm)/nvm.sh"
fi

if ! command -v npm &>/dev/null; then
  echo "Error: npm not found. Run 01_basics_linux.sh or 01_basics_macos.sh first." >&2
  exit 1
fi

# ── Node-based AI tools ───────────────────────────────────────────────────────

# Claude Code (Anthropic) — native installer
echo "Installing Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash

# Gemini CLI (Google)
echo "Installing Gemini CLI..."
npm install -g @google/gemini-cli

# GitHub Copilot CLI (via gh extension — gh already in basics)
echo "Installing GitHub Copilot CLI..."
gh extension install github/gh-copilot

# Pi coding agent (badlogic/pi-mono)
echo "Installing Pi coding agent..."
npm install -g @mariozechner/pi-coding-agent

# ── Python AI tools (via uv) ──────────────────────────────────────────────────

# Bootstrap uv if not present
if ! command -v uv &>/dev/null; then
  echo "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

# llm     — run/pipe prompts against any model, log history (Simon Willison)
# files-to-prompt — concat codebases into a single prompt
# ttok    — token counting before API calls
# strip-tags — strip HTML to clean text for LLM input
# aider   — AI pair programmer, git-native
for tool in llm files-to-prompt ttok strip-tags aider-chat; do
  echo "Installing $tool..."
  uv tool install "$tool"
done

echo ""
echo "Installed: claude, gemini, gh copilot, pi, llm, files-to-prompt, ttok, strip-tags, aider"
echo "Run 'claude' to get started with Claude Code."
