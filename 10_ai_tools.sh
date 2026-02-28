#!/bin/bash
# Phase 2 — Dev tools
# Installs AI coding assistants: Claude Code, Gemini CLI, GitHub Copilot CLI, Pi.
# Prerequisite: nodejs + npm (included in 01_basics_linux.sh / 01_basics_macos.sh)
set -euo pipefail

if ! command -v npm &>/dev/null; then
  echo "Error: npm not found. Run 01_basics_linux.sh or 01_basics_macos.sh first." >&2
  exit 1
fi

# Claude Code (Anthropic)
echo "Installing Claude Code..."
npm install -g @anthropic-ai/claude-code

# Gemini CLI (Google)
echo "Installing Gemini CLI..."
npm install -g @google/gemini-cli

# GitHub Copilot CLI (via gh extension — gh already in basics)
echo "Installing GitHub Copilot CLI..."
gh extension install github/gh-copilot

# Pi coding agent (badlogic/pi-mono)
echo "Installing Pi coding agent..."
npm install -g @mariozechner/pi-coding-agent

echo ""
echo "Installed: claude, gemini, gh copilot, pi"
echo "Run 'claude' to get started with Claude Code."
