#!/bin/bash
# Phase 10 — Claude Code CLI
# Installs Claude Code using Anthropic's native installer.
#
# Idempotent — safe to re-run. The installer places the launcher in
# ~/.local/bin/claude, which is on PATH after dotfiles are applied.
set -euo pipefail

if command -v claude &>/dev/null; then
  echo "Claude Code already installed: $(claude --version)"
  exit 0
fi

echo "Installing Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash

if command -v claude &>/dev/null; then
  echo "Claude Code installed: $(claude --version)"
else
  echo "Claude Code installer completed, but claude is not on PATH."
  echo "Expected location: ${HOME}/.local/bin/claude"
  echo "Add ${HOME}/.local/bin to PATH, then run: claude --version"
  exit 1
fi
