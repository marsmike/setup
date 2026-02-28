#!/bin/bash
# Phase 2 — LLM CLI utilities (Python / Simon Willison stack + aider)
# Prerequisite: python3 (included in 01_basics_linux.sh / 01_basics_macos.sh)
set -euo pipefail

# Bootstrap uv if not present
if ! command -v uv &>/dev/null; then
  echo "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

# llm          — run/pipe prompts against any model, log history (Simon Willison)
# files-to-prompt — concat codebases into a single prompt
# ttok         — token counting before API calls
# strip-tags   — strip HTML to clean text for LLM input
# aider-chat   — AI pair programmer, git-native
# (llmfit and timg are installed via brew in 01_basics_macos.sh)
for tool in llm files-to-prompt ttok strip-tags aider-chat; do
  echo "Installing $tool..."
  uv tool install "$tool"
done

echo ""
echo "Installed: llm, files-to-prompt, ttok, strip-tags, aider"
